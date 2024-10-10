<?

import('EntityManager');
import('ContactManager');

define('ALL_CUSTOMERS', 'All_Customers');

if(!defined("VARCHAR2_MIN")) {
    define("VARCHAR2_MIN", "\1");
}
if(!defined("VARCHAR2_MAX")) {
    define("VARCHAR2_MAX", json_decode('"\uDBFF\uDFFF"'));
}

class ConversionManager
{
    const MULTIPLE_SOURCE_DOCS = 'IA.MULTIPLE_SOURCE_TRANSACTIONS';

    const MAX_TASK_TIME         = (5 * 60.0);   // 5 minutes

    /**
     * @var string $_mod
     */
    var $_mod;

    /**
     * @var string[] $_recalledDocs
     */
    var $_recalledDocs = array();

    /**
     * @var int $_cny
     */
    var $_cny;

    /**
     * @var bool $_warningValidation
     */
    var $_warningValidation;

    /**
     * @var int $_cny
     */
    var $_multipleSourceDocsText;

    /**
     * @var bool
     */
    public static $documentIsBeingDeleted = false;

    /**
     * @var array $_sourcedocParCache
     */
    var $_sourcedocParCache = [];
    /**
     * @var array $_sourceDocCache
     */
    var $_sourceDocCache = [];

    /**
     * @var bool $isReverseConversionEnabled
     */
    private $isReverseConversionEnabled = false;

    /**
     * @var array $moduleType
     */
    private $moduleType =  [];

    /**
     * @param string[] $params
     */
    function __construct($params=array())
    {
        $this->_mod = $params['mod'];
        $this->_cny = GetMyCompany();
        $this->_warningValidation = $params['_warningValidation'];
        $this->_multipleSourceDocsText = self::getmultipleSourceDocsText();
    }

    /**
     * To return the multiple source transaction label.
     *
     * @return string
     */
    public static function getmultipleSourceDocsText()
    {
        return I18N::getSingleToken(self::MULTIPLE_SOURCE_DOCS);
    }

    /**
     * @param string $doctype
     *
     * @return array|string
     * @throws Exception
     */
    function GetAllowedDocsToConvertFrom($doctype)
    {
        // get all the list of doctypes to which we can convert from the doctype passed as parameter
        global $_userid, $gManagerFactory;
        if($doctype == '') {
            return array();
        }

        if(isset($this->_recalledDocs[$doctype])) {
            return $this->_recalledDocs[$doctype];
        }

        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$this->_mod];
        
        $docparMgr    = $gManagerFactory->getManager('documentparams');

        $allowedDocs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_RECALL_TO', array($spi, 'T', $doctype));
        $userId      = explode('@', $_userid);
        $userkey     = array_shift($userId);

        $allowedDocs = upermFilterResult($allowedDocs, $userkey);
        $allowedDocs = ( $allowedDocs ?: array() );
        $allowedDocs = filterDocsForUserType($allowedDocs);
        $alloweddoctypes = [];

        foreach($allowedDocs as $doc) {
            $alloweddoctypes[] = $doc['DOCID'];
        }

        $this->_recalledDocs[$doctype] = $alloweddoctypes;
        return $this->_recalledDocs[$doctype];
    }


    /**
     * @param string[]  $doctypes       an array of doctypes
     * @param bool      $inventoryFulfillmentOnly just include inventory fulfillment transactions?
     *
     * @return array|bool               an array of SOURCES and TARGETS for the given docid, in alpha order
     *                                  the ['SOURCES'] just are docids, and can be empty if this is the first
     *                                  the ['TARGETS'] are zero or more docids and whether they are marked as the default or not.
     *                                  if no targets, or too many to choose, an ['ERROR'] is returned
     *                                  ['BULK'] is the bulk path, or empty if none.
     *                                  or FALSE if there was an error
     */
    public function bulkConvertTo($doctypes, $inventoryFulfillmentOnly = false)
    {
        global $_userid;

        /**
         * for fulfillment, you can get the internal 'doc type'....
         * Note: this is a very abridged version of InvBizLogicForWD::documentTypeFromDocTree()
         *
         * @param string    $workflow           what is the 'Workflow' (internal: category) field?
         * @param string    $docclass           what is the doc class?
         *
         * @return string                       the internal form of the doc type
         */
        $docTypeFromCategory = function($workflow, $docclass) {
            if ((($docclass === 'ORDER') || ($docclass === 'LIST')) && ($workflow === 'O')) {
                return InvBizLogicForWD::TD_TYPE_SALESORDER;
            }
            if (($docclass === 'INVOICE') && ($workflow === 'I')) {
                return InvBizLogicForWD::TD_TYPE_INVOICE;
            }
            if ((($docclass === 'ORDER') || ($docclass === 'LIST')) && ($workflow === 'S')) {
                return InvBizLogicForWD::TD_TYPE_SHIPPER;
            }
            return InvBizLogicForWD::TD_TYPE_OTHER;
        };

        // **** MAIN CODE ****
        $rtn        = [];
        $modArray   = array('so' => 'S', 'po' => 'P', 'inv' => 'I', 'ALL' => 'SPI');
        $spi        = $modArray[$this->_mod];

        if( ! is_array($doctypes) || empty($doctypes)) {
            return $rtn;
        }

        $extraWhere = '';
        if ($inventoryFulfillmentOnly) {
            $extraWhere = " and docpar.enablefulfillment = 'T' ";
        }

        $qry   = [];
        $spiClause = ($spi === 'SPI') ? '' : 'and docpar.sale_pur_trans = :2 and recdpr.sale_pur_trans = :2';
        $qry[] = "SELECT recdpr.docid as sourcedocid, docpar.userperm, docpar.docid as docid, 
                         nvl(docrecalls.isdefault, 'F') as isdefault,
                         recdpr.category as categorySource, docpar.category as categoryTarget,
                         recdpr.docclass as docclassSource, docpar.docclass as docclassTarget,
                         recdpr.enablefulfillment as fulfillmentSource, docpar.enablefulfillment as fulfillmentTarget
                    FROM docpar, docrecalls, docpar recdpr 
                    WHERE docpar.cny# = :1 and docrecalls.cny# = docpar.cny# and recdpr.cny# = docpar.cny#
                      and docpar.latestversionkey is null and recdpr.latestversionkey is null 
                      $spiClause
                      and docpar.status = 'T' and recdpr.status = 'T' 
                      and docpar.RECORD# = docrecalls.DOCPARKEY
                      and docrecalls.RECDOCPARKEY = recdpr.record#  $extraWhere ";
        $qry[] = GetMyCompany();
        if ($spi !== 'SPI') {
            $qry[] = $spi;
        }
        $qry   = PrepINClauseStmt($qry, $doctypes, ' and recdpr.docid ');
        $qry[0] .= ' ORDER BY sourcedocid, docid ';
        $rows  = QueryResult($qry);
        if ($rows === false) {
            return false;
        }

        // now, filter out stuff not available to this user...
        $useridArray = explode('@', $_userid);
        $userkey     = array_shift($useridArray);
        $allowedDocs = upermFilterResult($rows, $userkey);
        $allowedDocs = filterDocsForUserType($allowedDocs);

        // connect the dots
        $graph = [];
        // NOTE: WATCH OUT FOR LOOPS!  A-->B-->A or A-->A
        foreach($allowedDocs as $row) {
            $source         = $row['SOURCEDOCID'] ?? '';
            $target         = $row['DOCID'] ?? '';
            $docTypeTarget  = $docTypeFromCategory($row['CATEGORYTARGET'], $row['DOCCLASSTARGET']);
            $docTypeSource  = $docTypeFromCategory($row['CATEGORYSOURCE'], $row['DOCCLASSSOURCE']);
            $fullTarget     = ['DOCID' => $target, 'DEFAULT' => ($row['ISDEFAULT'] === 'T')];
            if ($target != '') {
                if ( ! isset($graph[$source])) {
                    $graph[$source] = [];
                    $graph[$source]['TARGETS'] = [];
                    $graph[$source]['SOURCES'] = [];
                }
                $graph[$source]['TARGETS'][] = $fullTarget;
                $graph[$source]['DOCTYPE']   = $docTypeSource;
            }
            if ($source != '') {
                if ( ! isset($graph[$target])) {
                    $graph[$target] = [];
                    $graph[$target]['TARGETS'] = [];
                    $graph[$target]['SOURCES'] = [];
                }
                $graph[$target]['SOURCES'][] = ['DOCID' => $source];
                $graph[$target]['DOCTYPE']   = $docTypeTarget;
            }
        }

        // Do we trim?  Have errors?
        foreach ($graph as $docid => $sourcesAndTargets) {
            $targets = $sourcesAndTargets['TARGETS'] ?? [];
            $bulkPath = '';
            if (empty($targets) && ($sourcesAndTargets['DOCTYPE'] !== InvBizLogicForWD::TD_TYPE_INVOICE)) {
                $graph[$docid]['ERROR'] = sprintf( _("This document has no %s documents to convert to.  In the transaction definition, make sure there is a transaction to convert to, and try again."),
                    $inventoryFulfillmentOnly ? _("fulfillment-enabled") : ''  );
            } else {
                foreach ($targets as $oneTarget) {
                    if ($oneTarget['DEFAULT']) {
                        $bulkPath = $oneTarget['DOCID'];
                        break;
                    }
                }
                if ($bulkPath == '') {
                    $count = count($targets);
                    if ($count === 1) {
                        $bulkPath = $targets[0]['DOCID'];
                    } else if ($count > 1) {
                        $graph[$docid]['ERROR'] =
                            _("This document has too many documents it could convert to.  In the source transaction definition, check the 'Default' box on the 'Can be converted to' grid, and try again.");
                    }
                }
            }
            if ($bulkPath != '') {
                $graph[$docid]['BULK'] = $bulkPath;
            }
        }
        return $graph;
    }


    /**
     * @param string $doctype
     *
     * @return array|string
     * @throws Exception
     */
    function GetAllowedDocsToConvertTo($doctype)
    {
        global $_userid, $gManagerFactory;
        if($doctype == '') {
            return array();
        }

        if(isset($this->_recalledDocs[$doctype])) {
            return $this->_recalledDocs[$doctype];
        }

        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$this->_mod];

        $docparMgr    = $gManagerFactory->getManager('documentparams');

        $allowedDocs = $docparMgr->DoQuery('QRY_DOCUMENTPARAMS_ALLOWED_ACTIVE_RECALL_FROM', array($spi, $doctype));
        $userId      = explode('@', $_userid);
        $userkey     = array_shift($userId);

        $allowedDocs = upermFilterResult($allowedDocs, $userkey);
        $allowedDocs = ( $allowedDocs ?: array() );
        $allowedDocs = filterDocsForUserType($allowedDocs);
        $alloweddoctypes = [];

        foreach($allowedDocs as $doc) {
            $alloweddoctypes[] = $doc['DOCID'];
        }

        $this->_recalledDocs[$doctype] = $alloweddoctypes;
        return $this->_recalledDocs[$doctype];
    }

    /**
     * @param string[] $filterparams
     * @param string[][] $transactionlines
     */
    function GetAllConvertableTransactionLines($filterparams, &$transactionlines)
    {
        $sourceDocparID = $filterparams['convertfrom'];
        $custvend        = $filterparams['custvend'];
        $isMCPEnabled    = $filterparams['ismcpenabled'];
        $isAtlas        = IsMCMESubscribed();
        $basecurr        = $filterparams['basecurr'];
        $currency        = $filterparams['currency'];
        $maxrows        = ($filterparams['maxrows']!='' ? $filterparams['maxrows'] : 50);

        $fromItem    = $filterparams['fromItem'];
        $toItem        = $filterparams['toItem'];
        $fromDate    = $filterparams['fromDate'];
        $toDate        = $filterparams['toDate'];
        $dueDate    = $filterparams['dueDate'];
        $dueDateOperator = $filterparams['dueDateOperator'];
        $userid         = $filterparams['userid'];

        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$this->_mod];

        // define empty agruments
        $args = array('');
        
        $args[] = $spi;
        $args[] = $this->_cny;
        
        $argCnt = count($args)-1;

        /* ----------------- Customer/vendor Filters -------------------*/
        $custvnedSelects = "";
        $custvendTable    ="";
        $custvend_Join    = "";
        $custvend_Orderby = "";

        // if the customer / vendor parameter is missing then pull up all the data for all the customer/vendors
        if($custvend == '' || $custvend==ALL_CUSTOMERS) {
            if($this->_mod=='so') {
                $custvendTable = " customer entity, ";
                $custvnedSelects = " entity.customerid, entity.name customername, ";
                $custvend_Orderby = "entity.customerid, ";
            }else if($this->_mod=='po') {
                $custvendTable = " vendor entity, ";
                $custvnedSelects = " entity.vendorid, entity.name vendorname, ";
                $custvend_Orderby = "entity.vendorid, ";
            }
            $custvend_Join = " AND dochdr.entity = entity.entity (+) AND entity.cny#(+) = :2 ";
            $custvendFilter = " AND entity.onhold = 'F'";

        }else{
            $custvendFilter = " AND dochdr.entity = :".++$argCnt;

            list($custvendEntityID)    = explode('--', $custvend);
            $custvendprefix = ($this->_mod == 'po') ? 'V' : 'C';
            $custvendEntityID = $custvendprefix.$custvendEntityID;
            $args[] = $custvendEntityID;
        }
        /* ----------------- Customer/vendor Filters ends -------------------*/


        /* ----------------- Location Filters -------------------*/
        $locationFilter="";
        $ctx = '';
        if(IsMultiEntityCompany()) {
            $ctx = GetContextLocation();
            if($ctx!='') {
                $locationFilter = " AND dochdr.melocationkey = :".++$argCnt;
                $args[] = $ctx;
            }
        }
        /* ----------------- Location Filters ends -------------------*/


        /* ----------------- Date Filters -------------------*/
        // date filters
        if($fromDate =='' && $toDate =='') {
            $dateFilter = " ";
        }else{
            global $gAcctStartDate, $gAcctEndDate;
            if ( $fromDate == '' && $toDate != '') {
                $fromDate = $gAcctStartDate;
            }
            if ($toDate == '' && $fromDate != '') {
                $toDate = $gAcctEndDate;
            }
            $dateFilter = " and dochdr.whencreated BETWEEN :".++$argCnt." and :".++$argCnt;
            $args[] = $fromDate;
            $args[] = $toDate;
        }
        
        $duedateFilter = '';
        if($this->_mod=='so' && $dueDate !='' && $dueDateOperator!='') {
            $duedateFilter = " and dochdr.whendue ".$dueDateOperator." :".++$argCnt;
            $args[] = $dueDate;
        }
        /* ----------------- Date Filters ends -------------------*/


        /* ----------------- Item Filters -------------------*/
        list($fromitemid) = explode('--', $fromItem);
        $fromitemid    = $fromitemid ? isl_trim(isl_htmlspecialchars($fromitemid)) : VARCHAR2_MIN;
        list($toitemid)     = explode('--', $toItem);
        $toitemid    = $toitemid ? isl_trim(isl_htmlspecialchars($toitemid)) : VARCHAR2_MAX;

        if($fromitemid != '' && $toitemid != '') {
            $itemFilter = "and docentry.itemkey BETWEEN :".++$argCnt." and :".++$argCnt;
            $args[] = $fromitemid;
            $args[] = $toitemid;
        }else{
            $itemFilter = "";
        }
        /* ----------------- Item Filters ends -------------------*/


        /* ----------------- MCP/Atlas Filters -------------------*/
        // filter for mcp transaction lines based on currency if the company is mcp enabled.
        $mcpFilter = "";
        if($isMCPEnabled) {
            $currency = ($currency!='') ? $currency : $basecurr ;
            if($currency!='') {
                $mcpFilter = " AND dochdr.currency = :".++$argCnt;
                $args[] = $currency;
            }
        }

        $atlasFilter = '';
        if( $isAtlas && $ctx == '') {
            // the basecurr values comes from the filters for ATLAS companies at root
            $atlasFilter = " AND dochdr.basecurr = :".++$argCnt;
            $args[] = $basecurr;
        }
        /* ----------------- MCP/Atlas Filters ends -------------------*/


        /* ----------------- OE -> Term, Renewals, RevRec Filters -------------------*/
        $term_revrec_renewal_Join = '';
        $term_revrec_renewal_Table = '';
        $term_revrec_renewal_Selects = '';
        if($this->_mod=='so') {
            $term_revrec_renewal_Selects = "revrectemplate.templateid revrectemplate, docentry.revrectemplatekey,
                                                docentry.revrecstartdate, docentry.revrecenddate,
                                                docentry.itemterm, docentry.termperiod,
                                                docentry.prorateprice, docentry.deferrevenue,
                                                docentry.sc_revrecstartdate, docentry.sc_revrecenddate, docentry.sc_startdate,
                                                renewalmacro.macroid renewalmacro, docentry.renewalmacrokey, ";

            $term_revrec_renewal_Join = " and docentry.revrectemplatekey = revrectemplate.record#  (+)   and revrectemplate.cny# (+) = :2
										  and docentry.renewalmacrokey = renewalmacro.record#  (+)   and renewalmacro.cny# (+) = :2";

            $term_revrec_renewal_Table = "revrectemplate, renewalmacro, ";
        }
        /* ----------------- OE -> Term, Renewals, RevRec Filters ends -------------------*/

        /* ------------------- PO -> User filter for employee type users ---------------------------*/
        $userfilter = "";
        if ( ($this->_mod == 'po') && isset($userid)) {
            $userfilter = " AND dochdr.createduserkey = :".++$argCnt ;
            $args[] = $userid;
        }
        /* ------------------- PO -> User filter ends  ---------------------------------------------*/
        
        $args[0] = "SELECT   
					dochdr.docno, dochdr.ponumber, dochdr.currency, dochdr.whencreated, dochdr.state,
					dochdr.record# dockey, dochdr.docid, documentparams.status, dochdr.docparkey, dochdr.haschange,
					docentry.price, docentry.price_converted, docentry.value, 
					docentry.quantity, docentry.qty_converted, docentry.conversiontype,
					docentry.uiprice, docentry.uivalue, docentry.uiqty, docentry.unit,
					docentry.revisedunitqty, docentry.revisedqty,docentry.revisedprice, docentry.trx_revisedprice,
					docentry.trx_price, docentry.trx_value, docentry.discount_memo,
					docentry.record#, docentry.itemkey, docentry.itemdescr, docentry.memo, icitemcrossref.itemaliasid,
					docentry.lineno lineno, docentry.dochdrkey,docentry.ispartialexempt, docentry.billable,
					item.itemid, item.enablesno, item.enablelot, item.enablebin, item.enableexpiration,
					item.upc, item.itemtype, item.numdec_std, item.numdec_sale, item.numdec_pur,
					item.productlinekey productline, item.hasstartenddates, item.computeforshortterm,
					item.taxgroupkey, item.taxable, 
					docentry.deptkey, dept.dept_no, dept.title dept_title,
					docentry.locationkey, loc.location_no, loc.name loc_name,
					docentry.warehousekey, warehouse.name warehouse_name, warehouse.location_no warehouseid,
					$custvnedSelects
					$term_revrec_renewal_Selects
                    documentparams.docid docparid
				FROM
						dochdrmst dochdr,
						docparmst documentparams,
						docentry,
						$term_revrec_renewal_Table
						$custvendTable
						icitemmst item,
						icwarehousemst warehouse,
						departmentmst dept,
						locationmst loc,
						icitemcrossref
			   WHERE  documentparams.status = 'T'
				 AND documentparams.sale_pur_trans = :1
				 AND docentry.cny#(+) = :2
				 AND docentry.itemkey = item.itemid
				 AND item.cny#(+) = :2
				 AND docentry.warehousekey = warehouse.location_no(+)
				 AND warehouse.cny#(+) = :2
				 AND docentry.deptkey = dept.record#(+)
				 AND dept.cny#(+) = :2
				 AND docentry.locationkey = loc.record#(+)
				 AND loc.cny#(+) = :2
				 AND dochdr.docparkey = documentparams.record#(+)
				 AND documentparams.cny#(+) = :2
				 AND docentry.itemaliaskey = icitemcrossref.record#(+)   
                 AND icitemcrossref.cny#  (+)  = :2
				 $custvendFilter
				 $custvend_Join
				 AND dochdr.state IN ('O', 'P', 'B')
				 AND dochdr.cny# = :2
				 AND docentry.cny# = :2
				 AND docentry.dochdrkey = dochdr.record#(+)
				 AND ((NVL(docentry.conversiontype, 'Q') = 'Q' AND decode(dochdr.haschange, 'T', docentry.revisedqty, docentry.quantity) != NVL(docentry.qty_converted,0)) OR
				      (docentry.conversiontype = 'P' AND decode(dochdr.haschange, 'T', docentry.trx_revisedprice, docentry.trx_price)  != NVL(docentry.price_converted,0))) 
				 ";

        if(!is_array($sourceDocparID)) {
            $sourceDocparID = array($sourceDocparID);
        }
        $args = PrepINClauseStmt($args, $sourceDocparID, " AND documentparams.docid ", true, "docpar");
        
        $args[0] .= " $term_revrec_renewal_Join
				 $mcpFilter
				 $atlasFilter
				 $itemFilter
				 $dateFilter
				 $duedateFilter
				 $locationFilter
				 $userfilter
			ORDER BY $custvend_Orderby dochdr.whencreated, dochdr.docid, docentry.lineno";
        
        $result = QueryResult($args, 0, $maxrows);

        self::ProcessTransactionLines($currency, $result);

        foreach($result as $lineEntry){
            $transactionlines[$lineEntry['RECORD#']] = $lineEntry;
        }

    }

    /**
     * @param string $currency
     * @param string[][] $result
     *
     * @throws Exception
     */
    public static function ProcessTransactions($currency, &$result)
    {
        // We don't allow changing currency from source document for lines set to Price conversion.
        if (!isNullOrBlank($currency)) {
            if (POSetupManager::isPriceConversionEnabled() || SOSetupManager::isPriceConversionEnabled()) {
                global $gManagerFactory;
                $docEntryMgr = $gManagerFactory->getManager('documententry');
                $keysToRemove = [];
                foreach ($result as $key => $trans) {
                    if ($trans['CURRENCY'] != $currency) {
                        if (is_array($trans['ENTRIES_KEYS'])) {
                            foreach ($trans['ENTRIES_KEYS'] as $entry) {
                                $fullEntry = $docEntryMgr->get($entry);
                                if (!isNullOrBlank($fullEntry) && ($fullEntry['CONVERSIONTYPE'] == 'P' || $fullEntry['CONVERSIONTYPE'] == 'Price')) {
                                    $keysToRemove[] = $key;
                                    break;
                                }
                            }
                        }
                    }
                }
                $keysToRemove = array_reverse($keysToRemove);
                foreach ($keysToRemove as $keyToRemove) {
                    unset($result[$keyToRemove]);
                }
            }
        }
    }
    
    /**
     * @param string $currency
     * @param string[][] $result
     *
     * @throws Exception
     */
    public static function ProcessTransactionLines($currency, &$result)
    {
        global $gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');

        // We don't allow changing currency from source document for lines set to Price conversion.
        if (!isNullOrBlank($currency)) {
            $keysToRemove = [];
            foreach ($result as $key => $entry) {
                if (($entry['CONVERSIONTYPE'] == 'P' || $entry['CONVERSIONTYPE'] == 'Price') && $entry['CURRENCY'] != $currency) {
                    $keysToRemove[] = $key;
                }
            }
            $keysToRemove = array_reverse($keysToRemove);
            foreach ($keysToRemove as $keyToRemove) {
                array_splice($result, $keyToRemove, 1);
            }
        }
        
        $itemsArr = array();
        foreach ( $result as $entry ) {
            list($itemid) = explode('--', $entry['ITEMID']);
            if (!in_array($itemid, $itemsArr, true)) {
                $itemsArr[] = $itemid;
            }
        }

        $itemidAsKey = true;
        $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, $itemidAsKey);

        foreach ($result as $key => $entry ) {
            //splitting the itemid
            $itemMgr->GetLineEntry_UOMPrecissionInfo($entry, $uomInfoVals, $conversion, $uomPrecision);

            // get the remaining quantity to convert
            $remainingToConvert =
                ibcsub(self::getEntryConversionTypeQuantity($entry),
                    $entry[self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE'])], $uomPrecision, true);
            $originalQuantityorPrice = ibcdiv(self::getEntryConversionTypeQuantity($entry), $conversion, $uomPrecision, true);
            $availToConvert = ibcdiv($remainingToConvert, $conversion, $uomPrecision, true);

            if ($entry['CONVERSIONTYPE'] === 'Price' || $entry['CONVERSIONTYPE'] === 'P') {
                $result[$key]['ORGINAL_QTY'] = 1;
                $result[$key]['ORGPRICE'] = self::getEntryConversionTypeQuantity($entry);
                $result[$key]['AVAIL_QTY_TOCONVERT'] = ibcdiv($availToConvert, $originalQuantityorPrice, 2, true);
                $result[$key]['AVAIL_PRICE_TOCONVERT'] = $availToConvert;
            }
            else {
                $result[$key]['ORGINAL_QTY'] = $originalQuantityorPrice;
                $result[$key]['AVAIL_QTY_TOCONVERT'] = $availToConvert;
                $result[$key]['AVAIL_PRICE_TOCONVERT'] = null;
            }
        }
    }

    /**
     * @param string[] $filterparams
     * @param string[][] $transactions
     */
    function GetAllConvertableTransactions($filterparams, &$transactions)
    {
        $sourceDocparID = $filterparams['convertfrom'];
        $custvend        = $filterparams['custvend'];
        $isMCPEnabled    = $filterparams['ismcpenabled'];
        $isAtlas        = IsMCMESubscribed();
        $basecurr        = $filterparams['basecurr'];
        $currency        = $filterparams['currency'];
        $maxrows        = $filterparams['maxrows'];

        $fromItem    = $filterparams['fromItem'];
        $toItem        = $filterparams['toItem'];
        $fromDate    = $filterparams['fromDate'];
        $toDate        = $filterparams['toDate'];
        $dueDate    = $filterparams['dueDate'];
        $dueDateOperator = $filterparams['dueDateOperator'];
        $userid         = $filterparams['userid'];

        $locationFilter="";
        $ctx = '';
        if(IsMultiEntityCompany()) {
            $ctx = GetContextLocation();
            if($ctx!='') {
                $locationFilter = " AND dochdr.melocationkey = $ctx";
            }
        }
        
        $modArray = array('so' => 'S', 'po' => 'P', 'inv' => 'I');
        $spi = $modArray[$this->_mod];

        $custvendprefix        = ($this->_mod == 'po') ? 'V' : 'C';
        list($custvendEntityID) = explode('--', $custvend);
        $custvendEntityID = $custvendprefix.$custvendEntityID;

        $args = array('');
        $args[] = $spi;
        $args[] = $custvendEntityID;
        $args[] = $this->_cny;
        
        $argCnt = count($args)-1;

        // date filters
        if($fromDate =='' && $toDate =='') {
            $dateFilter = " ";
        }else{
            global $gAcctStartDate, $gAcctEndDate;
            if ( $fromDate == '' && $toDate != '') {
                $fromDate = $gAcctStartDate;
            }
            if ($toDate == '' && $fromDate != '') {
                $toDate = $gAcctEndDate;
            }
            $dateFilter = " and dochdr.whencreated BETWEEN :".++$argCnt." and :".++$argCnt;
            $args[] = $fromDate;
            $args[] = $toDate;
        }
        
        $duedateFilter = '';
        if($this->_mod=='so' && $dueDate !='' && $dueDateOperator!='') {
            $duedateFilter = " and dochdr.whendue ".$dueDateOperator." :".++$argCnt;
            $args[] = $dueDate;
        }

        // item filters
        list($fromitemid) = explode('--', $fromItem);
        $fromitemid    = $fromitemid ? isl_trim(isl_htmlspecialchars($fromitemid)) : VARCHAR2_MIN;
        list($toitemid)     = explode('--', $toItem);
        $toitemid    = $toitemid ? isl_trim(isl_htmlspecialchars($toitemid)) : VARCHAR2_MAX;

        if($fromitemid != '' && $toitemid != '') {
            $itemFilter = "and docentry.itemkey BETWEEN :".++$argCnt." and :".++$argCnt;
            $args[] = $fromitemid;
            $args[] = $toitemid;
        }else{
            $itemFilter = "";
        }
        
        // filter for mcp transaction based on currency if the company is mcp enabled.
        $mcpFilter = "";
        if($isMCPEnabled) {
            $currency = ($currency!='') ? $currency : $basecurr ;
            if($currency!='') {
                $mcpFilter = " AND dochdr.currency = :".++$argCnt;
                $args[] = $currency;
            }

            $totalamt = ' round(sum(round(docentry.uiqty*docentry.trx_price,2)) ,2) totalamt ';
            $totalremainingamt = ' round(sum(round((docentry.uiqty-docentry.qty_converted)*docentry.trx_price,2)) ,2) totalremainingamt ';
        }else{
            $totalamt = ' round( sum(round(docentry.uiqty*docentry.uiprice,2)) ,2) totalamt ';
            $totalremainingamt = ' round(sum(round((docentry.uiqty-docentry.qty_converted)*docentry.uiprice,2)) ,2) totalremainingamt ';
        }


        $atlasFilter = '';
        if( $isAtlas && $basecurr != '' && $ctx == '') {
            // the basecurr values comes from the filters for ATLAS companies at root
            $atlasFilter = " AND dochdr.basecurr = :".++$argCnt;
            $args[] = $basecurr;
        }

        /* ------------------- PO -> User filter for employee type users ---------------------------*/
        $userfilter = "";
        if ( ($this->_mod == 'po') && isset($userid)) {
            $userfilter = " AND dochdr.createduserkey = :".++$argCnt;
            $args[] = $userid;
        }
        /* ------------------- PO -> User filter ends  ---------------------------------------------*/

        $args[0] = "SELECT  documentparams.docid docparid, dochdr.docno, dochdr.ponumber,
							 dochdr.whencreated, dochdr.whendue, docentry.record# docentrykey, docentry.conversiontype,
							 dochdr.currency, dochdr.docid, dochdr.record#, $totalamt , $totalremainingamt
						FROM dochdrmst dochdr, docpar documentparams,  docentry 
					    WHERE  
					     documentparams.status = 'T'                         
						 AND documentparams.sale_pur_trans = :1							 
						 AND dochdr.docparkey = documentparams.record#(+)
						 AND documentparams.cny#(+) = :3
						 AND docentry.dochdrkey = dochdr.record#
						 AND docentry.cny# = :3						 
						 AND dochdr.entity = :2
						 AND dochdr.state IN ('O', 'P' , 'B')
						 AND dochdr.cny# = :3 ";
						         
        if(!is_array($sourceDocparID)) {
            $sourceDocparID = array($sourceDocparID);
        }
        $args = PrepINClauseStmt($args, $sourceDocparID, "AND documentparams.docid ", true, "docpar");
        
        $groupby = "GROUP BY  dochdr.whencreated, dochdr.docno,
					 dochdr.whendue, dochdr.docid, 
					 dochdr.ponumber, documentparams.docid, dochdr.record#, docentry.record#, docentry.conversiontype,
					 dochdr.currency
					ORDER BY dochdr.whencreated, dochdr.record#";

        $args[0] .= " $mcpFilter
						 $atlasFilter
						 $itemFilter
						 $dateFilter
						 $duedateFilter
						 $locationFilter
						 $userfilter
						$groupby";

        $result = QueryResult($args, 0, $maxrows);

        foreach($result as $trans){
            $transactions[$trans['RECORD#']] = $trans;
        }

        foreach( ($transactions ?? []) as $tkey => $trans){
            $docentrykeys = array();
            $tot_amt = 0;
            $total_remaining_amt = 0;
            foreach( $result as $entry){
                if($entry['RECORD#'] == $tkey) {
                    $docentrykeys[] = $entry['DOCENTRYKEY'];
                    $tot_amt = $tot_amt + $entry['TOTALAMT'];
                    $total_remaining_amt = $total_remaining_amt + $entry['TOTALREMAININGAMT'];
                }
            }
            $transactions[$tkey]['ENTRIES_KEYS'] = $docentrykeys;
            $transactions[$tkey]['TOTALAMT'] = $tot_amt;
            $transactions[$tkey]['TOTALREMAININGAMT'] = $total_remaining_amt;
        }
        
        self::ProcessTransactions($currency, $transactions);
    }

    /**
     * @param string $mod
     *
     * @return array
     */
    function GetAllDocumentTypes($mod)
    {
        $result = GetDocumentMenuList($mod);

        $manager = Globals::$g->gManagerFactory->getManager('document');
        $result = $manager->removeChangeDocuments($result);
        $result = $manager->removePCBDocuments($result);

        $docparMgr = Globals::$g->gManagerFactory->getManager('documentparams');
        $result = $docparMgr->removeFulfillmentbDocuments($result);

        $doctypes = [];
        foreach($result as $res) {
            $doctypes[] = $res['DOCID'];
        }

        return $doctypes;
    }

    /**
     * @param array     $values
     * @param bool $reverse
     *
     * @return bool
     */
    // incase of multiple document conversion update the all the source documents
    function ProcessUpdateRecall(&$values, $reverse=false)
    {
        $ok = true;
        $sourceDocs = array();
        $enableDocChange = isNullOrBlank($values["_DOCPAR"]["ENABLEDOCCHANGE"]) ? "No Change" : $values["_DOCPAR"]["ENABLEDOCCHANGE"];

        if($enableDocChange == "Change Order"){
            $sourceDocs[] = $values["RELATEDDOCNO"];
        }else{
            // get the unique list of source document keys from line entries
            foreach( $values['ENTRIES'] as $entry){
                $sourceDocid = $entry['SOURCE_DOCID'];
                if(isset($sourceDocid) && $sourceDocid!='') {
                    if(!in_array($sourceDocid, $sourceDocs)) {
                        $sourceDocs[] = $sourceDocid;
                    }
                } else if (isset($entry['ISSUMMARIZED']) && $entry['ISSUMMARIZED'] == 'true' &&
                    (!isset($entry['SOURCE_LINETYPE']) || $entry['SOURCE_LINETYPE'] != 'TIMEANDMATERIAL')
                ) {
                    // For summarized entries, use the summarybilleddetail to get associated sourceDocs.
                    $summaryBillManager = Globals::$g->gManagerFactory->getManager('summarybilleddetail');
                    $summaryBillDetail = $summaryBillManager->getByDocEntryKey($entry['RECORDNO']);
                    $documentManager = Globals::$g->gManagerFactory->getManager('sodocumententry');
                    foreach ($summaryBillDetail as $summaryEntry) {
                        if (isset($summaryEntry['DOCENTRYKEY'])) {
                            $summaryDocEntry = $documentManager->GetByRecordNo($summaryEntry['DOCENTRYKEY'], ['DOCHDRID']);
                            if (is_array($summaryDocEntry) && !in_array($summaryDocEntry['DOCHDRID'], $sourceDocs)) {
                                $sourceDocs[] = $summaryDocEntry['DOCHDRID'];
                            }
                        }
                    }
                }
            }
        }

        // updating source document(s)
        if (!empty($sourceDocs) && is_array($sourceDocs)) {
            //Prepare sourceDocCache for each sourceDocIds
            $this->prepareSourceDocCache($sourceDocs);
            foreach($sourceDocs as $sourceDocid){
                $ok = $ok && $this->UpdateRecall($sourceDocid, $values, $reverse);
            }
        }

        return $ok;
    }

    /**
     * This function gives you necessary field values for updateRecall function.
     * It will save processing time at Edit and Post
     *
     * @param $sourceDocs
     *
     */
    public function prepareSourceDocCache($sourceDocs)
    {
        //ProcessDeleteOrSet - time takes 18.028 Sec
        //ProcessConvert - time takes 15.934 Sec

        $srcDocIds = [];
        if ( Util::countOrZero($sourceDocs) > 0 ) {
            foreach ( $sourceDocs as $srcDocId ) {
                if ( ! empty($srcDocId) ) {
                    $srcDocIds[$srcDocId] = $srcDocId;
                }
            }
        }

        if ( Util::countOrZero($srcDocIds) > 0 ) {

            //First get all docparkeys from sourceDocIds then prepare sourceDocparCache with DOCPARKEY as key
            $docMgr = Globals::$g->gManagerFactory->getManager('document');

            $params = [];
            $sourceDocparKeyMap = [];
            $params['nodbfilters'] = true;
            $params['selects'] = [ 'DISTINCT DOCPARKEY AS DOCPARKEY', 'DOCPARID' ];
            $params['filters'] = [ [ [ 'DOCID', 'IN', array_keys($srcDocIds) ] ] ];
            $result = $docMgr->GetList($params);
            foreach ($result ?? [] as $val){
                $sourceDocparKeyMap[$val['DOCPARKEY']] = $val;
            }

            //Preparing DocumentParams cache
            $this->prepareSourceDocparCache($sourceDocparKeyMap);

            foreach ( $srcDocIds ?? [] as $srcDocId ) {
                //should we use below if condition?
                if ( ! isset($this->_sourceDocCache[$srcDocId]) ) {

                    $srcDocType = $this->getSourceDocumentType($srcDocId);
                    $srcDocMgr = $this->getSourceDoctypeManager($srcDocType);
                    $srcDocEntryMgr = $this->getSourceDocEntryManager($srcDocType);

                    //selecting required fields for each sourceDocId
                    $params['nodbfilters'] = true;
                    $params['selects'] =
                        [ 'RECORDNO', 'DOCID', 'DOCPARKEY', 'DOCPARID', 'DOCNO', 'STATE', 'MELOCATIONKEY', 'WHENCREATED',
                          'BACKORDER', 'SALESCONTRACT' ];
                    $params['filters'] = [ [ [ 'DOCID', '=', $srcDocId ] ] ];
                    $result = $srcDocMgr->GetList($params)[0];

                    $this->_sourceDocCache[$result['DOCID']] = $result;
                    $this->_sourceDocCache[$result['DOCID']]['ENTRIES'] =
                        $srcDocEntryMgr->GetByParent($result['RECORDNO']);
                    //check for tracking entries and append same to sourceDocCache
                    $this->prepareSourceDocTrackingEntries($this->_sourceDocCache[$result['DOCID']]);

                    $this->_sourceDocCache[$result['DOCID']]['_DOCPAR'] =
                            $this->_sourcedocParCache[$result['DOCPARKEY']];

                }
            }
        }
    }

    /**
     *
     * array $sourceDoc
     */
    private function prepareSourceDocTrackingEntries(&$sourceDocDetails)
    {
        $docEntryKeys = [];
        $doctrackMgr = Globals::$g->gManagerFactory->getManager('documententrytrackdetail');
        foreach ($sourceDocDetails['ENTRIES'] as $entry) {
            $docEntryKeys[] = $entry['RECORDNO'];
        }
        $trackingEntries = $doctrackMgr->getManyByParent($docEntryKeys);

        // now attach the entries to the docentry records.....
        if ( Util::countOrZero($trackingEntries) > 0 ) {
            foreach ( $sourceDocDetails['ENTRIES'] as $key => $entry ) {
                if ( isset($trackingEntries[$entry['RECORDNO']]) ) {
                    $this->_sourceDocCache[$sourceDocDetails['DOCID']]['ENTRIES'][$key]['TRACKINGENTRIES'] =
                        $trackingEntries[$entry['RECORDNO']];
                }
            }
        }
    }

    /**
     * @return object|string
     */
    private function getSourceDocEntryManager($sourceDocType)
    {
        // Get the instance of recalled/source document entry manager
        $recalledDocEntryMgr = Globals::$g->gManagerFactory->getManager($this->_mod . 'documententry', false,
                                                                        [ 'DOCTYPE' => $sourceDocType ]);

        $recalledDocEntryMgr->_isCachable = false;

        return $recalledDocEntryMgr;
    }

    /**
     * @param $docparkeys
     *
     */
    private function prepareSourceDocparCache($docparkeys)
    {
        //fetch required fields from DocumentParams for each sourcDocIds
        $docParMgr = Globals::$g->gManagerFactory->getManager('documentparams');

        $docparams['nodbfilters'] = true;
        $docparams['selects'] =
            [ 'RECORDNO', 'DOCID', 'CONVTYPE', 'ENABLEDOCCHANGE', 'DISPLAY_BASECURRENCY', 'ENABLE_RETAINAGE',
              'DISCOUNT_ON_EXTENDEDPRICE', 'SALE_PUR_TRANS', 'STATUS', 'USERPERM', 'DOCCLASS', 'ALLOW_ALLOCATIONS',
              'RENEWONLYCONVERTEDLINE', 'UPDATES_INV', 'ENABLERENEWALS', 'ENABLEFULFILLMENT', 'ENABLEALLOCRESERVE' ];
        $docparams['filters'] = [ [
                                      [ 'RECORDNO', 'IN', array_keys($docparkeys) ],
                                  ] ];
        $result = $docParMgr->GetList($docparams);
        foreach ( $result ?? [] as $val ) {
            $this->_sourcedocParCache[$val['RECORDNO']] = $val;
        }
    }

    /**
     * @param string $sourceDocID
     * @param string $sourceDocType
     *
     * @return array
     */
    public function getSourceDocument($sourceDocID, $sourceDocType)
    {
        /**
         * @var DocumentManager $recalledDocMgr
         */
        $recalledDocMgr = $this->getSourceDoctypeManager($sourceDocType);

        /**
         * @var DocumentParamsManager $docparMgr
         */
        $docparMgr = $recalledDocMgr->get_docpar_manager();

        $resetSession = false;
        if (IsMultiEntityCompany()
            && (IsUserLocRestricted()
                || IsUserDepRestricted())) {
            $_sess = Session::getKey();
            SetUserContext($_sess, '', '', 'F');
            $resetSession = true;
        }


        // Get the recalled document
        $sourceDoc = $recalledDocMgr->Get($sourceDocID);

        // need to split the itemid-itemname to have only item
            if (!empty($sourceDoc['ENTRIES']) && is_array($sourceDoc['ENTRIES'])) {
            foreach ($sourceDoc['ENTRIES'] as $key => $pEntry) {
                $item = $pEntry['ITEMID'];
                list($item) = explode('--', $item);
                $sourceDoc['ENTRIES'][$key]['ITEMID'] = $item;
            }
        }
        if (!$sourceDoc['_DOCPAR']) {
            $sourceDoc['_DOCPAR'] = $docparMgr->BaseGet($sourceDoc['DOCPARKEY']);
        }

        if ($resetSession == true) {
            $_sess = Session::getKey();
            SetUserContext($_sess, 'T', GetContextLocation(), 'T');
        }

        return $sourceDoc;
    }

        /**
     * @param string $sourceDocID
     *
     * @return string
     */
    private function getSourceDocumentType($sourceDocID)
    {
        // Find out recalled document's doctype (DOCPAR.docid)
        $recalledDocTypeQry = "select docid from docpar where cny# = :1 and exists "
            . "(select 1 from dochdr where cny# = :1 and docid = :2 and docparkey = docpar.record#)";
        $recalledDocTypeRes = QueryResult(array($recalledDocTypeQry, GetMyCompany(), $sourceDocID));
        $recalledDocType = $recalledDocTypeRes[0]['DOCID'];

        return $recalledDocType;
    }

        /**
     * @param string $sourceDocType
     *
     * @return object
     */
    private function getSourceDoctypeManager($sourceDocType)
    {
        $dmgr = isl_strtoupper($this->_mod) . "DocumentManager";

        // Get the instance of recalled/source document manager
        $recalledDocMgr = Globals::$g->gManagerFactory->_getObjectInstance(
            $dmgr, false, array('DOCTYPE' => $sourceDocType, 'skipAllocations' => true)
        );

        $recalledDocMgr->_isCachable = false;

        return $recalledDocMgr;
    }


    /**
     * Update the recalled document state
     *
     * @param  string  $sourceDocID recalled document id.
     * @param  array   $currentDoc  values of the current document.
     * @param bool $deletingChild
     *
     * @return bool returns if the method execution was success or not.
     */
    function UpdateRecall($sourceDocID, &$currentDoc, $deletingChild = false)
    {
        $ok = true;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $newState = '';

        /**
         * @var DocumentManager $docMgr
         */
        $docMgr = $gManagerFactory->getManager($this->_mod . "document");
        $recalledDocType =
            isset($this->_sourceDocCache[$sourceDocID]) ? $this->_sourceDocCache[$sourceDocID]['DOCPARID']
                : $this->getSourceDocumentType($sourceDocID);

        /**
         * @var DocumentManager $recalledDocMgr
         */
        $recalledDocMgr = $this->getSourceDoctypeManager($recalledDocType);
        // Get the Source document data, if its not cached
        if ( !empty($this->_sourceDocCache) && ! isset($this->_sourceDocCache[$sourceDocID]) ) {
            $this->_sourceDocCache[$sourceDocID] = $this->getSourceDocument($sourceDocID, $recalledDocType);
        }

        //Keep original variable name as it is, assign cached sourceDoc values
        //It will reduce changes in every function its called
        $sourceDoc = $this->_sourceDocCache[$sourceDocID];
        $enableDocChange = isNullOrBlank($currentDoc["_DOCPAR"]["ENABLEDOCCHANGE"]) ? "No Change" : $currentDoc["_DOCPAR"]["ENABLEDOCCHANGE"];
        if($enableDocChange == "Change Order" && ($currentDoc["STATE"] == DocumentManager::DRAFT_STATE || $sourceDoc["STATE"] != DocumentManager::PARTIALLY_CONVERTED_STATE)){
            return true;
        }

        $sourceDocpar = $sourceDoc['_DOCPAR'];
        $conversionType = $sourceDocpar['CONVTYPE'];

        // get the 'Partial Convertion Handling' configuration of the source document
        $leaveSourceDocOpen = ($conversionType == 'Leave Transaction Open') ? true : false;
        if ($currentDoc['CLOSESOURCEDOC']) {
            $leaveSourceDocOpen = false;
        }


        // update the recalled state to Done, or Open the recalled document if reverse is set to true
        if ($deletingChild) {
            //
            $state = $this->getRecalledDocState($sourceDoc, $currentDoc, $deletingChild);
            $ok = $ok && $docMgr->DoQuery('QRY_DOCUMENT_SETSTATE', array($state, $sourceDocID));

            $ok = $ok && $this->UpdateValueConverted($sourceDoc, $currentDoc, $deletingChild);

            if (self::$documentIsBeingDeleted) {
                $wqManager = Globals::$g->gManagerFactory->getManager('inventoryworkqueue');
                $ok = $ok && $wqManager->ResurrectTheDead($sourceDoc, $currentDoc); // if this earlier doc was IN fulfillment, resurrect it now.
            }

            //Check to see if a back order exists, delete if any.
            $backOrder = $docMgr->DoQuery('QRY_DOCUMENT_GET_BACKORDER_IDS', array($sourceDoc['RECORDNO']));
            $backOrder = $backOrder[0];

            // if there are any back orders created from this source document.
            // delete the backorders only if they are in Draft or Pending state
            if (!empty($backOrder) &&
                ( $backOrder['STATE'] == DocumentManager::PENDING_RAWSTATE
                || $backOrder['STATE'] == DocumentManager::DRAFT_RAWSTATE)
            ) {
                    $ok = $ok && $docMgr->deleteWithOverride($backOrder['DOCID'], true);
                }

        } else {
            $this->isReverseConversionEnabled = $this->isReverseConversionAllowed($sourceDoc);

            if (
                $sourceDoc['STATE'] == DocumentManager::PENDING_STATE
                || $sourceDoc['STATE'] == DocumentManager::PARTIALLY_CONVERTED_STATE
                || $sourceDoc['STATE'] == DocumentManager::PARTIALLY_CONVERTED_BY_LINE_STATE
                || $sourceDoc['STATE'] == DocumentManager::INPROGRESS_STATE

            ) {
                if ($leaveSourceDocOpen) {
                    $newState = $this->getRecalledDocState($sourceDoc, $currentDoc);
                } else {
                    if ($currentDoc['STATE'] == DocumentManager::DRAFT_STATE) {
                        $newState = DocumentManager::INPROGRESS_RAWSTATE;
                    } else {
                        $newState = DocumentManager::CONVERTED_RAWSTATE;
                    }
                }
                $ok = $ok && $docMgr->DoQuery('QRY_DOCUMENT_SETSTATE', array($newState, $sourceDocID));
            }

            if($this->isReverseConversionEnabled && $sourceDoc['STATE'] == DocumentManager::CONVERTED_STATE){
                $isReverseConversionLineExist = $this->isReverseConversionLineExist($currentDoc['ENTRIES']);
                if ($leaveSourceDocOpen && $isReverseConversionLineExist) {
                    $newState = $this->getRecalledDocState($sourceDoc, $currentDoc);
                    $ok = $ok && $docMgr->DoQuery('QRY_DOCUMENT_SETSTATE', array($newState, $sourceDocID));
                }
            }

            if($enableDocChange != "Change Order"){ // CheckMatchingLineItems validation is not required for Change document
                // Check if adding / changing line item is allowed
                // check if increasing the quantities allowed
                $ok = $ok && $this->CheckMatchingLineItems($sourceDoc, $currentDoc);
            }
            //
            // Validate if the sourceDoc lines have been fully converted (i.e. QTY_CONVERTED >= QTY)
            $ok = $ok && $this->validateDocument($sourceDoc, $currentDoc);

            $ok = $ok && $this->convertingFromAndToPrimaryDoc($sourceDoc, $currentDoc);

            $createBackOrder = ($conversionType == 'Close Original and Create Back Order') ? true : false;

            if ($createBackOrder && $currentDoc['STATE'] != 'Draft') {
                // if we are creating multiple transactions from
                if ($currentDoc['AUTO_DOC_PROCESS']['CONVERSION_TYPE'] == 'L'
                    && $currentDoc['AUTO_DOC_PROCESS']['CONVERSION_METHOD'] == 'I') {
                    if ($currentDoc['AUTO_DOC_PROCESS']['CREATE_BACK_ORDER']) {
                        $ok = $ok && $this->CreateBackOrder($sourceDoc, $currentDoc);
                    }
                } else {
                    $ok = $ok && $this->CreateBackOrder($sourceDoc, $currentDoc);
                }
            } else {
                $ok = $ok && $this->UpdateValueConverted($sourceDoc, $currentDoc);
            }
        }

        $currentDoc['SOURCEDOCPARDETAIL'] = $sourceDocpar;
        $currentDoc['SOURCEDOCDETAIL'] = $sourceDoc;

        if (!$deletingChild) {
            //For Renewals do BaseGet only if below conditions true
            if(
                $sourceDoc['STATE'] == DocumentManager::CONVERTED_STATE
                && $sourceDoc['_DOCPAR']['ENABLERENEWALS'] =='Generate'
                && $sourceDoc['_DOCPAR']['RENEWONLYCONVERTEDLINE'] == 'true'
            ) {
                $this->prepareSourceDoc($sourceDoc);
            }
            $sourceDoc['STATE'] = $newState;
            $ok = $ok && $docMgr->CreateDocConvRenewals($sourceDoc);
        }
        //To set state of converted document at SFDC.
        if ($ok) {
            $forcenew = false;
            //If parent DocType is different from current document then
            //only we need to have a new instance of obj by making $forcenew = true
            if ($recalledDocType != $currentDoc['_DOCPAR']['DOCID']) {
                $forcenew = true;
            }
            $recalledDocMgr->DoEvent('Set', $docMgr->GetKeyValue($sourceDoc), '', $forcenew, false);
        }

        return $ok;
    }

    /**
     * @param $backOrder
     *
     * @return void
     */
    function prepareBackorder(&$backOrder)
    {
        $this->prepareSourceDoc($backOrder);

        //prepareSourceDoc doesn't fetch subtotals data, due to which we must fetch subtotals explicitly.
        //For backorder transactions we need Subtotals. First check the TD config and then prepare subtotals
        if ( $backOrder['_DOCPAR']['SHOW_TOTALS'] == 'true' ) {
            $docSubtotalMgr = Globals::$g->gManagerFactory->getManager('documentsubtotals');
            $backOrder['SUBTOTALS'] = $docSubtotalMgr->GetByParent($backOrder['RECORDNO']);
        }

        //get the sourceDoc's attachment for backorder transactions
        GetSupDocId($backOrder, 'DOCHDR');
    }

    /**
     * @param $sourceDoc
     *
     * @return void
     */
    private function prepareSourceDoc(&$sourceDoc)
    {
        /*
        * With conversion manager optimization, we are considering limited fields for sourceDocs using GetList.
        * For Renewals, BackOrders we require complete header fields - we are doing baseGet to fetch entire values
        * re-assigning ENTRIES, DOCPAR values to make complete object
        */

        $docMgr = Globals::$g->gManagerFactory->getManager($this->_mod . 'document',
                                                           true,
                                                           ['DOCTYPE' => $sourceDoc['_DOCPAR']['DOCID']]
        );
        $docparMgr = Globals::$g->gManagerFactory->getManager($this->_mod .'documentparams');

        $entries = $sourceDoc['ENTRIES'];
        $sourceDoc = $docMgr->BaseGet($sourceDoc['DOCID']);
        $sourceDoc['ENTRIES'] = $entries;
        $sourceDoc['_DOCPAR'] = $docparMgr->BaseGet($sourceDoc['DOCPARKEY']);
    }


    /**
     * Get the recalled document state
     *
     * @param  array[]   $oldDoc     values of the old document.
     * @param  array[]   $currentDoc values of the current document.
     * @param bool $deletingChild
     *
     * @return string returns the state of the recalled document.
     */
    function getRecalledDocState($oldDoc, $currentDoc, $deletingChild = false)
    {

        $newEntries = $currentDoc['ENTRIES'];
        // parent document
        $oldEntries = $oldDoc['ENTRIES'];

        $this->isReverseConversionEnabled = $this->isReverseConversionAllowed($oldDoc);

        // when deleting the current document subtract the current documents quantity converted
        // else add the current documents quantity converted for each line
        foreach($oldEntries as $key => $entry) {
            foreach( $newEntries as $newentry) {
                if ($this->doOldAndNewEntriesMatch($entry, $newentry)) {
                    $conversionTypeLabel = self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE']);
                    $newValue = self::getEntryConversionTypeQuantity($newentry, $entry);

                    if($this->isReverseConversionEnabled){
                         $this->prepareReverseConversionFieldValues($oldEntries[$key], $newentry, $deletingChild);
                    }

                    if ($deletingChild) {
                        $oldEntries[$key][$conversionTypeLabel] = ibcsub(
                            $oldEntries[$key][$conversionTypeLabel], $newValue, ItemManager::BASEUNITPRECISION
                        );
                    } else {
                        $oldEntries[$key][$conversionTypeLabel] = ibcadd(
                            $oldEntries[$key][$conversionTypeLabel], $newValue, ItemManager::BASEUNITPRECISION
                        );
                    }

                    break;
                }
            }
        }

        // if all the line items have the quantity converted value as 0 which means the document state must be 'Pending'
        $count=0;
        foreach( $oldEntries as $entry) {

            $conversionTypeLabel = self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE']);

            if($this->isReverseConversionEnabled){
                $stdConvertedFieldType = $this->getStandardConversionFieldType($conversionTypeLabel);
                $reverseConvertedFieldType = $this->getReverseConversionFieldType($conversionTypeLabel);
                if($entry[$conversionTypeLabel]==0 && $entry[$stdConvertedFieldType]==0 && $entry[$reverseConvertedFieldType]==0) {
                    $count++;
                }
            }else{
                if($entry[$conversionTypeLabel]==0) {
                    $count++;
                }
            }

        }

        // if all the line items have the quantity equal to quantity converted which means all the line are conveted and the document state must be 'Converted'
        $fullyConvertedCount = 0;
        foreach( $oldEntries as $entry) {

            $conversionTypeLabel = self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE']);

            //
            // rounding off to 5 (max decimal UOM supports) decimals becuase PHP float comparision is not 100% correct
            $value_converted = round($entry[$conversionTypeLabel], 5);
            $value = round(self::getEntryConversionTypeQuantity($entry), 5);

            $isReverseConversionLine = $this->isReverseConversionLine($entry);

            $stdConvertedFieldType = $this->getStandardConversionFieldType($conversionTypeLabel);
            $reverseConvertedFieldType = $this->getReverseConversionFieldType($conversionTypeLabel);
            if($this->isReverseConversionEnabled && ($isReverseConversionLine || ($deletingChild
              && ((!empty($entry[$stdConvertedFieldType]) && $entry[$stdConvertedFieldType] != 0) ||
                  (!empty($entry[$reverseConvertedFieldType]) && $entry[$reverseConvertedFieldType] != 0))))){
                    if(ibcsub(ibcabs($entry[$stdConvertedFieldType]), ibcabs($entry[$reverseConvertedFieldType])) >= ibcabs($value)){
                        $fullyConvertedCount++;
                    }
            }else{
                if ( ibcabs($value_converted) >= ibcabs($value)) {
                    $fullyConvertedCount++;
                }
            }

        }

        if (!$deletingChild && $currentDoc['STATE'] == DocumentManager::DRAFT_STATE) {
            $state = DocumentManager::INPROGRESS_RAWSTATE;
        } else if ($count == Util::countOrZero($oldEntries)) {
            $state = DocumentManager::PENDING_RAWSTATE;
        } else if ($fullyConvertedCount == Util::countOrZero($oldEntries)) {
            $state = DocumentManager::CONVERTED_RAWSTATE;
        } else {
            $state = DocumentManager::PARTIALLY_CONVERTED_RAWSTATE;
        }

        return $state;
    }

    /**
     * @param string $conversionType
     * @return string $conversionTypePrefix
     */
    private static function getConversionType_ConvertedValue($conversionType) {

        $conversionTypePrefix = 'QTY_CONVERTED';

        if ($conversionType === 'Price' || $conversionType === 'P') {
            $conversionTypePrefix = 'PRICE_CONVERTED';
        }

        return $conversionTypePrefix;
    }

    /**
     * @param [] $entry
     * @return string $conversionTypePrefix
     */
    private static function getConversionTypeSourceValue($entry) {
        $conversionTypePrefix = 'QUANTITY';

        if ($entry['CONVERSIONTYPE'] === 'Price' || $entry['CONVERSIONTYPE'] === 'P') {
            if (!isNullOrBlank($entry['TRX_PRICE'])) {
                $conversionTypePrefix = 'TRX_PRICE';
            }
            else {
                $conversionTypePrefix = 'UIPRICE';
            }
        }

        return $conversionTypePrefix;
    }

    /**
     * Check for matching line items in the old and current documents.
     *
     * @param  [] $oldDoc     old document values.
     * @param  [] $currentDoc values of the current document.
     * @return bool returns if the method execution was success or not.
     */
    function CheckMatchingLineItems($oldDoc, $currentDoc)
    {
        $ok = true;
        global $gErr;

        $this->isReverseConversionEnabled = $this->isReverseConversionAllowed($oldDoc);

        $newEntries = [];
        if(($currentDoc['CREATEDFROM'] ?? '') == $this->_multipleSourceDocsText) {
            $parentDocid = $oldDoc['DOCID'];
            // filter all the entries from this parent
            foreach( $currentDoc['ENTRIES'] as $entry){
                if($parentDocid == $entry['SOURCE_DOCID']) {
                    $newEntries[] = $entry;
                }
            }
        }else{
            $newEntries = $currentDoc['ENTRIES'];
        }

        // Validate a change in conversiontype prior to other validations regarding quantity or price.
        foreach($oldDoc['ENTRIES'] as $entry) {
            $item = $entry['ITEMID'];
            foreach ($newEntries as $newentry) {
                if ($item == $newentry['ITEMID'] && $entry['RECORDNO'] == $newentry['SOURCE_DOCLINEKEY']) {
                    if (!$this->validateConversionTypeChange($entry, $newentry)) {
                        $ok = false;
                    }
                }
            }
        }

        //
        // skip further validation if Quantity change or Item change is allowed in the PO/OE/Inv module setup
        if(isQuantityChangeAllowedWhenConverting($this->_mod)){
           return $ok;
        }

        $this->processBackOrderQuantities($oldDoc);

        $oldEntries = $oldDoc['ENTRIES'];

        /*
        In case where transaction have more than one line with the same item,
        make sure that the number of lines for each item is the same in the recalled transaction
        */
        $itemMatching = [];

        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        foreach ($oldEntries as $entry) {
            $sourceEntryKey = $entry['ITEMID'] . '~' . $entry['DOCHDRNO'] . '~' . $entry['RECORDNO'];
            if ($docMgr->isIncludeFullyConvertedLineAllowed($this->_mod) || $entry[self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE'])] != self::getEntryConversionTypeQuantity($entry)) {
                $itemMatching[$sourceEntryKey]['sourceEntryCount'] += 1;
                $itemMatching[$sourceEntryKey]['ITEMID'] = $entry['ITEMID'];
            }
        }

        foreach ($newEntries as $newentry) {
            if ((isset($newentry['ALLOCATIONKEY']) && $newentry['ALLOCATIONKEY'] !== '')
                && (isset($newentry['SOURCE_SPLIT']) && count($newentry['SOURCE_SPLIT']) > 0)
                && (isset($newentry['SPLIT']) && count($newentry['SPLIT']) > 0)) {
                continue;
            }

            // skip the retainage billing line through PGI for the validation
            if(CRESetupManager::isRetainageBillingEnabled() && isset($newentry['ISRETAINAGERELEASE']) && $newentry['ISRETAINAGERELEASE'] == "true"){
                continue;
            }

            $sourceEntryKey = $newentry['ITEMID'] . '~' . ($newentry['SOURCE_DOCKEY'] ?? '') . '~' . ($newentry['SOURCE_DOCLINEKEY'] ?? '');
            if (!$this->isSummarized($newentry)) {
                $itemMatching[$sourceEntryKey]['childEntryCount'] += 1;
            }
            $itemMatching[$sourceEntryKey]['ITEMID'] = $newentry['ITEMID'];
            if (!isset($newentry['SOURCE_DOCKEY']) || !isset($newentry['SOURCE_DOCLINEKEY'])) {
                $itemMatching[$sourceEntryKey]['NEWLYADDEDLINEITEMS'][] = $newentry['LINE_NO'] + 1;
            }

            if($this->isReverseConversionEnabled && $this->isReverseConversionLine($newentry)){
                // when we try to add reverse conversion line to fully converted document, the sourceEntryCount should have count or else validation will be triggered
                if(empty($itemMatching[$sourceEntryKey]['sourceEntryCount'])){
                    $itemMatching[$sourceEntryKey]['sourceEntryCount'] = 1;
                }
            }

        }

        foreach ($itemMatching as $sourceEntryKey => $itemData) {
            if ($itemData['childEntryCount'] >= 1
                && ($itemData['sourceEntryCount'] ?? 0) == 0
                && !$docMgr->isIncludeFullyConvertedLineAllowed($this->_mod)
                && !(in_array($currentDoc['STATE'], [DocumentManager::DRAFT_STATE, DocumentManager::ANALYZING_STATE]))) {
                $newlineNumbers = implode(',', (array_unique($itemData['NEWLYADDEDLINEITEMS'] ?? [])));
                $errorMsg = "You cannot add a new entry using an item that does not exist in the originating ";
                $errorMsg .= "transaction or a new entry using an item that already exists in the transaction.";
                if(strlen($newlineNumbers) > 0){
                     $correctionErrorMsg = "Delete line $newlineNumbers Then, try again.";
                     $errorCode = 'INV-0324';
                     $correctionPlaceholder = ['NEWLINE_NUMBERS' => $newlineNumbers];
                }
                else{
                     $correctionErrorMsg = '';
                     $errorCode = 'INV-0325';
                     $correctionPlaceholder = [];
                }
                $gErr->addIAError(
                    $errorCode, __FILE__ . ':' . __LINE__,
                    $errorMsg, [], '', [],
                    $correctionErrorMsg,$correctionPlaceholder
                );
                $ok = false;
            }
        }

        // Do not allow increasing quantities or sign change
        foreach($oldEntries as $key => $entry) {

            $item = $entry['ITEMID'];
            $oldQty = self::getEntryConversionTypeQuantity($entry) - $entry[self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE'])];

            foreach($newEntries as $k2 => $newentry) {

                if ($item == $newentry['ITEMID'] && $entry['RECORDNO'] == $newentry['SOURCE_DOCLINEKEY']) {
                    $newQty = self::getEntryConversionTypeQuantity($newentry, $entry);

                    //Do not allow sign change of quantities during conversion
                    if ($oldQty != 0 && $newQty != 0) {
                        $oldSign = ($oldQty < 0) ? -1 : 1;
                        $newSign = ($newQty < 0) ? -1 : 1;

                        if ($oldSign != $newSign && !$this->isReverseConversionLine($newentry)) {
                            if($newSign < 0){
                                $newSignStr = 'negative';
                                $errorCode = 'INV-0326';
                            }
                            else{
                                 $newSignStr = 'positive';
                                  $errorCode = 'INV-0327';
                            }
                            $gErr->addIAError(
                                $errorCode, __FILE__.':'.__LINE__,
                                'The quantity for item '.$item.' of the recalled transaction on line number '.($key+1). ' is '.$oldQty.' which cannot be converted to a '.$newSignStr.' number',
                                ['ITEM' => $item,'KEY_PLUS_1' => $key+1, 'OLD_QTY' => $oldQty]
                            );
                            $ok = false;
                        }
                    }

                    //Do not allow increasing quantities
                    // the max number of decimals for quantity, uiqty & qty_converted is 4 in DB
                    if ($ok && ibcabs(round($newQty, 4)) > ibcabs(round($oldQty, 4)) && !$this->isReverseConversionLine($newentry)
                        && !(in_array($currentDoc['STATE'], [DocumentManager::DRAFT_STATE, DocumentManager::ANALYZING_STATE]))) {
                        if ($newentry['CONVERSIONTYPE'] === 'Price') {
                            $newQtyRound = iround($newQty, 2);
                            $gErr->addIAError(
                                'INV-0328', __FILE__ . ':' . __LINE__,
                                sprintf('Line No:%3$s of the recalled Order transaction: Maximum price for itemID %1$s is %2$s. New price %4$s.', $item, $oldQty, ($key + 1), $newQtyRound),
                                ['ITEM' => $item, 'OLD_QTY' => $oldQty, 'KEY_PLUS_1' => ($key + 1), 'NEW_QTY_ROUND' => $newQtyRound]
                            );
                        }
                        else {
                            $gErr->addIAError(
                                'INV-0329', __FILE__ . ':' . __LINE__,
                                "You cannot increase the quantity of an item during conversion.",[],
                                '', [],
                                sprintf('Enter a quantity for line %1$s that is less than or equal to %2$s. Then, try again.', ($key + 1), $oldQty),
                                ['KEY_PLUS_1' => ($key + 1), 'OLD_QTY' => $oldQty]
                            );
                        }
                        $ok = false;
                    }
                    unset($newEntries[$k2]);
                    break;
                }
            }
        }

        return $ok;
    }

    /**
     * @param array $newEntry the new entry
     *
     * @return bool
     */
    private static function isSummarized($newEntry)
    {
        $isSummarized = (isset($newEntry['ISSUMMARIZED_ENTRY']) && ($newEntry['ISSUMMARIZED_ENTRY'] == 'true')) ||
            (isset($newEntry['ISSUMMARIZED']) && ($newEntry['ISSUMMARIZED'] == 'true'));
        return $isSummarized;
    }

    /**
     * @param array $sourceDoc
     *
     * @return bool
     */
    protected function processBackOrderQuantities(&$sourceDoc)
    {
        $dmgr = isl_strtoupper($this->_mod)."DocumentManager";
        $docMgr = Globals::$g->gManagerFactory->_getObjectInstance(
            $dmgr, false, array('DOCTYPE' => $sourceDoc['_DOCPAR']['DOCID'])
        );
        $docMgr->_isCachable = false;
        $backOrder = $docMgr->DoQuery('QRY_DOCUMENT_GET_BACKORDER_IDS', array($sourceDoc['RECORDNO']));
        $backOrder = $backOrder[0];

        if (empty($backOrder)) {
            return true;
        }

        // back order document type will same as that of the source document
        $bOrderDocType = $sourceDoc['_DOCPAR']['DOCID'];

        $gManagerFactory = Globals::$g->gManagerFactory;
        /**
         * @var DocumentEntryManager $docentryMgr
         */
        $docentryMgr = $gManagerFactory->getManager($this->_mod . 'documententry',
            true,
            array('DOCTYPE' => $bOrderDocType));
        $backOrderEntries = $docentryMgr->GetByParent($backOrder['RECORD#']);

        if (empty($backOrderEntries)) {
            return true;
        }

        foreach ($sourceDoc['ENTRIES'] as &$sEntry) {
            list($sItemId) = explode('--', $sEntry['ITEMID']);

            foreach ($backOrderEntries as $bEntry) {
                list($bItemId) = explode('--', $bEntry['ITEMID']);

                if ($sItemId == $bItemId
                    && $sEntry['DOCHDRNO'] == $bEntry['SOURCE_DOCKEY']
                    && $sEntry['RECORDNO'] == $bEntry['SOURCE_DOCLINEKEY']) {

                    $sEntry['QTY_CONVERTED'] = ibcadd(
                        $sEntry['QTY_CONVERTED'], self::getEntryQuantity($bEntry), ItemManager::BASEUNITPRECISION
                    );
                    if ($sEntry['CONVERSIONTYPE'] === 'P') {
                        $sEntry['PRICE_CONVERTED'] = ibcadd(
                            $sEntry['PRICE_CONVERTED'], $bEntry['PRICE_CONVERTED'], ItemManager::BASEUNITPRECISION
                        );
                    }
                }
            }
        }

        return true;
    }

    /**
     * Create the back order record.
     *
     * @param  array $oldDoc     old document values.
     * @param  array $currentDoc values of the current document.
     * @return bool returns if the method execution was success or not.
     */
    private function CreateBackOrder($oldDoc, $currentDoc)
    {
        global $gManagerFactory;
        $itemMgr    = $gManagerFactory->getManager('item');
        $dmgr = isl_strtoupper($this->_mod) . "document";
        $docMgr = Globals::$g->gManagerFactory->getManager($dmgr,
            true,
            ['DOCTYPE' => $oldDoc['_DOCPAR']['DOCID']]
        );
        
        $docMgr->_isCachable = false;
        $ret = $docMgr->DoQuery('QRY_DOCUMENT_GET_BACKORDER_IDS', array($oldDoc['RECORDNO']));
        
        // if backorder already created then, system skipped to delete existing back order
        // since backorder might have been converted already.
        // So skip creating back order
        if (!empty($ret)) {
            $ok = $this->UpdateValueConverted($oldDoc, $currentDoc);
            return $ok;
        }
        
        $ok = true;
        $oldEntries = $oldDoc['ENTRIES'];
        $newEntries = [];

        $this->prepareBackorder($oldDoc);

        if(($currentDoc['CREATEDFROM'] ?? '') == $this->_multipleSourceDocsText) {
            $parentDocid = $oldDoc['DOCID'];
            // filter all the entries from this parent
            foreach( $currentDoc['ENTRIES'] as $entry){
                if($parentDocid == $entry['SOURCE_DOCID']) {
                    $newEntries[] = $entry;
                }
            }
        }else{
            $newEntries = $currentDoc['ENTRIES'];
        }

        $itemsArr = array();
        foreach ( $oldEntries as $entry ) {
            list($itemid) = explode('--', $entry['ITEMID']);
            if (!in_array($itemid, $itemsArr, true)) {
                $itemsArr[] = $itemid;
            }
        }

        $hasAllocations = false;
        $itemidAsKey = true;
        $uomInfoVals = $itemMgr->GetUOMInfoCache($itemsArr, $itemidAsKey);
        $precision = DEFAULT_INVPRECISION;
        $boEntries = [];

        //Creating any backorders
        // ----------------------------------------------------------------------
        //	Take the line item diff of the old and current document
        // ----------------------------------------------------------------------
        foreach( $oldEntries as $entry) {
            $newQty = 0;
            $item = $entry['ITEMID'];
            $oldQty = ibcsub(self::getEntryConversionTypeQuantity($entry), $entry[self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE'])], ItemManager::BASEUNITPRECISION);

            // Get the conversion factor
            //$uomInfo = $itemMgr->GetUOMInfoCache(array($item), true);
            $uomInfo        = $uomInfoVals[$item];
            $conversion        = $uomInfo[$entry['UNIT']]['CONVFACTOR'] ?: 1;
            $uomPrecision     = $uomInfo[$entry['UNIT']]['NUMDEC'];
            $uom_is_base = $uomInfo[$entry['UNIT']]['ISBASE'];

            $uomPrecision = ($uomPrecision > 0 && $uom_is_base != 'T') ? $uomPrecision : ItemManager::BASEUNITPRECISION;

            $newentry = [];
            foreach( $newEntries as $k2 => $newentry) {
                //while conversion, if we remove one item in current document, then the below if condition will never get satisfied and $precison is undefined, hence moving this statement here
                $precision = (isset($newentry['PRECISION']) && $newentry['PRECISION']!='') ? $newentry['PRECISION'] : DEFAULT_INVPRECISION;
                if (($item == $newentry['ITEMID'] || (isset($newentry['ISSUMMARIZED_ENTRY']) && $newentry['ISSUMMARIZED_ENTRY'] == 'true')) 
                    && $entry['RECORDNO'] == $newentry['SOURCE_DOCLINEKEY']
                ) {
                    $newQty = self::getEntryConversionTypeQuantity($newentry);
                    unset($newEntries[$k2]);
                    break;
                }
            }

            // if the new quantity for that item is less than the old doc, we
            // will need a back order for those items.
            if (ibcabs($newQty) < ibcabs($oldQty)) {
                $boentry = $entry;
                unset($boentry['RECORDNO']);
                $boQty = ibcdiv(ibcsub($oldQty, $newQty, ItemManager::BASEUNITPRECISION, true), $conversion, $uomPrecision, true);

                if ($boentry['CONVERSIONTYPE'] === 'Price') {
                    $boentry['UIQTY'] = 1;
                    $boentry['PRICE'] = $boQty;
                    $boentry['TRX_PRICE'] = $boQty;
                    $boentry['UIPRICE'] = $boQty;
                    $boentry['TRX_VALUE'] = $boQty;
                }
                else {
                    $boentry['UIQTY'] = $boQty;
                    $boentry['UIPRICE'] = ibcmul($entry['PRICE'], $conversion, $precision);
                }

                if ($oldDoc['_DOCPAR']['DISCOUNT_ON_EXTENDEDPRICE']
                    === 'true'
                ) {
                    $boentry['UIVALUE'] = calcValueOnExtendedPrice(
                        $boentry['UIQTY'], $boentry['UIPRICE'],
                        $boentry['MULTIPLIER'],
                        $boentry['DISCOUNTPERCENT']
                    );

                } else {
                    if ($boentry['CONVERSIONTYPE'] === 'Price') {
                        $boentry['UIVALUE'] = $boQty;
                    }
                    else {
                        $boentry['UIVALUE'] = ibcmul($boentry['UIQTY'], $boentry['UIPRICE'], 2);
                    }
                }

                $boentry['TOTAL'] = $boentry['UIVALUE'];
                $boentry['SOURCE_DOCKEY'] = $entry['DOCHDRNO'];
                $boentry['SOURCE_DOCLINEKEY'] = $entry['RECORDNO'];
                $boentry['SOURCE_DOCID'] = $oldDoc['DOCID'];

                $boentry['RETAINAGEPERCENTAGE'] = $entry['RETAINAGEPERCENTAGE'];
                $boentry['TRX_AMOUNTRETAINED'] = '';
                $boentry['AMOUNTRETAINED'] = '';

                if ((isset($boentry['ALLOCATIONKEY']) && $boentry['ALLOCATIONKEY'] !== '')) {
                    $hasAllocations = true;
                }

                if (ibcabs($boentry['UIQTY']) > 0) {
                    if(isset($boentry['TRACKINGENTRIES']) && is_array($boentry['TRACKINGENTRIES'])){
                        $trackingHandler = new TrackingHandler(array('ACTION' => CREATE_ACTION));
                        $trackingHandler->copyToBackOrder($entry, $newentry, $boentry);
                    }

                    $boEntries[] = $boentry;
                }
            }
        }
        
        // update quantity converted
        $ok = $ok && $this->UpdateValueConverted($oldDoc, $currentDoc);

        if ( count($boEntries) > 0) {
            $backOrder = $oldDoc;
            $backOrder['CREATEDFROM'] = $oldDoc['DOCID'];
            $backOrder['ENTRIES'] = $boEntries;
            $backOrder['STATE'] = DocumentManager::PENDING_STATE;
            $backOrder['NOTE'] = 'BACK ORDER for ' . $oldDoc['DOCID'] ;
            $backOrder['BACKORDER'] = 'Yes';
            $backOrder['_do'] = 'create';
            // unseting the prrecordkey, addglbatchkey & prinvbatchkey as back orders doesnt hit apar/gl
            // so the prbatchkey, addglbatchkey & prinvbactkey are actually assined from parent which are not valid.
            unset($backOrder['PRRECORDKEY']);
            unset($backOrder['PRINVBATCHKEY']);
            unset($backOrder['ADDGLBATCHKEY']);
            unset($backOrder['RECORDNO']);

            if($hasAllocations) {
                $docMgr->applyAllocationForGet($backOrder);
            }

            $docMgr->_warningValidation = $this->_warningValidation;
            $ok = $ok && $docMgr->add($backOrder);
        }

        return $ok;
    }

    /**
     * @param array $entry
     * @param array $newentry
     * @return bool
     */
    private function doOldAndNewEntriesMatch($entry, $newentry)
    {
        if (isset($newentry['ISSUMMARIZED_ENTRY']) && $newentry['ISSUMMARIZED_ENTRY'] == 'true') {
            $itemsMatch = true;
        } else {
            $itemsMatch = ($entry['ITEMID'] == $newentry['ITEMID']);
        }
        $entryRecordMatch = ($entry['RECORDNO'] == $newentry['SOURCE_DOCLINEKEY']);
        if (isset($newentry['ISSUMMARIZED']) && $newentry['ISSUMMARIZED'] == 'true') {
            // For summarized entries, use summarybilleddetail to determine a matching source doc line.
            // Also, ignore item matching in this case.
            $itemsMatch = true;
            $entryRecordMatch = false;
            $summaryBillDetailManager = Globals::$g->gManagerFactory->getManager('summarybilleddetail');
            $summaryList = $summaryBillDetailManager->getByDocEntryKey($newentry['RECORDNO'], $entry['RECORDNO']);
            if (isNonEmptyArray($summaryList)) {
                $entryRecordMatch = true;
            }
        }
        
        return ($itemsMatch && $entryRecordMatch);
    }

    /**
     * @param array $oldDoc
     * @param array $currentDoc
     * @param bool  $reverse
     *
     * @return bool
     * @throws Exception
     */
    function UpdateValueConverted(&$oldDoc, $currentDoc, $reverse=false)
    {
        $ok = true;

        $enableDocChange = isNullOrBlank($currentDoc["_DOCPAR"]["ENABLEDOCCHANGE"]) ? "No Change" : $currentDoc["_DOCPAR"]["ENABLEDOCCHANGE"];
        if($enableDocChange == "Change Order"){
            return true;
        }

        // Parent Document
        $oldEntries = $oldDoc['ENTRIES'];
        $newEntries = $this->filterForNewEntries($oldDoc, $currentDoc);

        $isMCPEnabled = IsMCPEnabled($this->_mod);

        /* when deleting subtract the current documents line items quantity from
        source documents line items quantity converted
        else add increase the quantity converted value of source document
        */
        $convertedEntries = array();
        $this->isReverseConversionEnabled = CRESetupManager::isReverseConversionEnabled();
        foreach($oldEntries as $key => $entry) {
            foreach ($newEntries as $k2 => $newentry) {
                if ($this->doOldAndNewEntriesMatch($entry, $newentry)) {
                    $newValue = $this->getEntryConversionTypeQuantity($newentry, $entry);
                    $conversionTypeLabel = self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE']);

                    if ($reverse) {
                        $entry[$conversionTypeLabel] = ibcsub(
                            $oldEntries[$key][$conversionTypeLabel], $newValue, ItemManager::BASEUNITPRECISION
                        );
                    } else {
                        $entry[$conversionTypeLabel] = ibcadd(
                            $oldEntries[$key][$conversionTypeLabel], $newValue, ItemManager::BASEUNITPRECISION
                        );
                    }

                    if ($entry['CONVERSIONTYPE'] == "Price") {
                        $entry['QTY_CONVERTED'] = ibcdiv($entry['PRICE_CONVERTED'],
                            isNullOrBlank($entry['TRX_PRICE']) ? $entry['PRICE'] : $entry['TRX_PRICE'],2, true);
                    }

                    $this->prepareReverseConversionFieldValues($entry, $newentry, $reverse);

                    $convertedEntries[$entry['RECORDNO']] = $entry;
                    if (!isset($newEntries[$k2]['ISSUMMARIZED']) || $newEntries[$k2]['ISSUMMARIZED'] != 'true') {
                        unset($newEntries[$k2]);
                    }
                    break;
                }
            }
        }
        
        $oldDoc['ENTRIES'] = $oldEntries = $convertedEntries;

        // Updating the source document entry quantity converted
        $docEntryMgr = Globals::$g->gManagerFactory->getManager('documententry');
        
        $nonInventoryItems = array(
            'Non-Inventory', 
            'Non-Inventory (Purchase only)',
            'Non-Inventory (Sales only)'
        );

        foreach ($oldEntries as $key => $entry) {

            $conversionTypeLabel = self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE']);
            $value = self::getEntryConversionTypeQuantity($entry);

            $stdConvertedFieldType = $this->getStandardConversionFieldType($conversionTypeLabel);
            $reverseConvertedFieldType = $this->getReverseConversionFieldType($conversionTypeLabel);

            $args = array($oldEntries[$key][$conversionTypeLabel], $oldEntries[$key]['RECORDNO'], $this->_cny);
            if (isset($entry[$conversionTypeLabel])) {
                // if the parent document is not affecting on hand
                // or item is non inventory then no validation required
                if (
                    $oldDoc['_DOCPAR']['UPDATES_INV'] == 'No'
                    || in_array($entry['ITEM']['ITEMTYPE'], $nonInventoryItems)
                    || (
                        ($value >= 0 && $entry[$conversionTypeLabel] >= 0
                            && $entry[$conversionTypeLabel] <= $value)
                        || ($value <= 0 && $entry[$conversionTypeLabel] <= 0
                            && $entry[$conversionTypeLabel] >= $value)
                    )
                    || in_array($currentDoc['STATE'], [DocumentManager::DRAFT_STATE, DocumentManager::ANALYZING_STATE])
                ) {

                    $qry = 'QRY_DOCUMENTENTRY_SET_' . $conversionTypeLabel;
                    $ok = $ok && $docEntryMgr->DoQuery($qry, $args);


                    $qry = 'QRY_DOCUMENTENTRY_SET_REV_' . $conversionTypeLabel;
                    $args = [$entry[$reverseConvertedFieldType] ?? 0, $entry['RECORDNO'], $this->_cny];
                    $ok = $ok && $docEntryMgr->DoQuery($qry, $args);

                    $qry = 'QRY_DOCUMENTENTRY_SET_STD_' . $conversionTypeLabel;
                    $args = [$entry[$stdConvertedFieldType] ?? 0, $entry['RECORDNO'], $this->_cny];
                    $ok = $ok && $docEntryMgr->DoQuery($qry, $args);

                    if ($conversionTypeLabel === 'PRICE_CONVERTED') {
                        if($isMCPEnabled){
                            $price = !isNullOrBlank($oldEntries[$key]['TRX_REVISEDPRICE']) ? $oldEntries[$key]['TRX_REVISEDPRICE'] : $oldEntries[$key]['TRX_PRICE'];
                        }else{
                            $price = !isNullOrBlank($oldEntries[$key]['REVISEDPRICE']) ? $oldEntries[$key]['REVISEDPRICE'] : $oldEntries[$key]['PRICE'];
                        }
                        $qtyConverted = ibcdiv($oldEntries[$key]['PRICE_CONVERTED'], $price, 10);
                        $args = array($qtyConverted, $oldEntries[$key]['RECORDNO'], $this->_cny);
                        $qry = 'QRY_DOCUMENTENTRY_SET_QTY_CONVERTED';
                        $ok = $ok && $docEntryMgr->DoQuery($qry, $args);

                        $qry = 'QRY_DOCUMENTENTRY_SET_REV_QTY_CONVERTED';
                        $args = [$entry['REVERSEQTYCONVERTED'] ?? 0, $entry['RECORDNO'], $this->_cny];
                        $ok = $ok && $docEntryMgr->DoQuery($qry, $args);

                        $qry = 'QRY_DOCUMENTENTRY_SET_STD_QTY_CONVERTED';
                        $args = [$entry['STDQTYCONVERTED'] ?? 0, $entry['RECORDNO'], $this->_cny];
                        $ok = $ok && $docEntryMgr->DoQuery($qry, $args);
                    }

                } else {
                    Globals::$g->gErr->addIAError(
                        'INV-0006', __FILE__ . ':' . __LINE__,
                        'Cannot convert more than available quantity.', [],
                        'Please enter valid quantity to convert.', []
                    );
                    return false;
                }
            }

            // REVERSECONVERSION is set inside prepareReverseConversionFieldValues method and removing now
            unset($oldDoc['ENTRIES'][$key]['REVERSECONVERSION']);
        }

        return $ok;
    }

    /**
     * back end validation to prevent a document from being converted twice
     *
     * @param array $values transaction
     *
     * @return bool
     */
    public static function validateConversion($values)
    {
        $ok = true;
        if ( !empty($values['CREATEDFROM'] ?? '')) {
            $sourceDocs = array();
            // get the unique list of source document keys from line entries
            // this document may be converted from multiple source transactions
            if($values['CREATEDFROM'] == self::getmultipleSourceDocsText()) {
                foreach( $values['ENTRIES'] as $entry){
                    $sourceDocid = $entry['SOURCE_DOCID'];
                    if(isset($sourceDocid) && $sourceDocid!='') {
                        if(!in_array($sourceDocid, $sourceDocs)) {
                            $sourceDocs[] = $sourceDocid;
                        }
                    }
                }
            } else {
                $sourceDocs[] = $values['CREATEDFROM'];
            }
            if(count($sourceDocs) > 0 && !in_array($values['DOCPARID'],
                                        array(ICTransferManager::INDOCTYPE, ICTransferManager::INTRANSITDOCTYPE))) {
                foreach($sourceDocs as $sourceDocid){
                    $ok = $ok && self::isDocumentConvertable($sourceDocid);
                }
            }

        }

        return $ok;
    }

    /**
     * @param string $sourceDocid               the doc id
     * @param string $sourceDocState            the document state, if you already know it
     *
     * @return bool
     * @throws Exception
     */
    public static function isDocumentConvertable($sourceDocid, $sourceDocState = '')
    {
        $gErr = Globals::$g->gErr;
        $ok   = true;
        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        $mod = "";
        if ($sourceDocState == '') {
            $qry = array(
                'selects' => array('STATE'),
                'filters' => array(array(
                    array('DOCID', '=', $sourceDocid),
                )),
            );

            $sourceDoc = $docMgr->GetList($qry);

            if (empty($sourceDoc)) {
                $msg = 'No Document with the ID ' . $sourceDocid . ' exists.';
                $gErr->addIAError(
                    'INV-0319', __FILE__ . ':' . __LINE__,
                    $msg, ['SOURCE_DOCID' => $sourceDocid],
                    'Please use a valid Document as your source.', []
                );
                return false;
            }
            $sourceDocState = $sourceDoc[0]['STATE'];

        }

        $qry = [
            'selects' =>['SALE_PUR_TRANS'],
            'filters' => [[['DOCID', '=', $sourceDocid]]],
        ];

        $docMod = $docMgr->GetList($qry);
        if(!empty($docMod[0])){
            if($docMod[0]["SALE_PUR_TRANS"] == 'Sale'){
                $mod = "so";
            }elseif($docMod[0]["SALE_PUR_TRANS"] == 'Purchase'){
                $mod = "po";
            }
        }

        $msg = '';

        switch ($sourceDocState) {
            case DocumentManager::CLOSED_STATE:
                $msg = sprintf('Document %1s is %2s. Unable to convert.', $sourceDocid, $sourceDocState );
                $errorCode = 'INV-0330';
                $placeHolder = ['SOURCE_DOCID' => $sourceDocid, 'SOURCE_DOC_STATE' => $sourceDocState];
                break;

            case DocumentManager::CONVERTED_STATE:
            case DocumentManager::CONVERTED_BY_LINE_STATE:
                if($docMgr->isReverseConversionAllowed($mod) && $sourceDocState != DocumentManager::CONVERTED_BY_LINE_STATE){
                    break;
                }
                $msg = sprintf('Document %1s is already %2s. Unable to convert.', $sourceDocid, $sourceDocState );
                $errorCode = 'INV-0331';
                $placeHolder = ['SOURCE_DOCID' => $sourceDocid, 'SOURCE_DOC_STATE' => $sourceDocState];
                break;

            case DocumentManager::SUBMITTED_STATE:
            case DocumentManager::APPROVED_STATE:
            case DocumentManager::PARTIALLY_APPROVED_STATE:
            case DocumentManager::DECLINED_STATE:
            case DocumentManager::DRAFT_STATE:
                $msg = sprintf('Document %1s is in %2s state. Unable to convert.', $sourceDocid, $sourceDocState );
                $errorCode = 'INV-0332';
                $placeHolder = ['SOURCE_DOCID' => $sourceDocid, 'SOURCE_DOC_STATE' => $sourceDocState];
                break;

            case DocumentManager::INPROGRESS_STATE:
                $msg = sprintf('Document %1s is in progress of conversion into another document. Unable to convert.', $sourceDocid );
                $errorCode = 'INV-0333';
                $placeHolder = ['SOURCE_DOCID' => $sourceDocid];
                break;

            default:
                // no error
        }

        if ($msg) {
            $gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeHolder);
            $ok = false;
        }

        return $ok;
    }

    /**
     * @param array $sourceDoc
     * @param array $currentDoc
     *
     * @return bool
     */
    private function convertingFromAndToPrimaryDoc($sourceDoc, $currentDoc)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;


        // check if $currentDoc is a primary doc
        $gManagerFactory = Globals::$g->gManagerFactory;
        $poDocumentParamsMgr = $gManagerFactory->getManager('podocumentparams');

        if ($poDocumentParamsMgr->isPrimaryDocEnabled($currentDoc['DOCPARID'])) {

            // if primarydoc keys are set on any of the $oldDoc entries then we are attempting to convert an upstream primarydoc
            // to another primarydoc downstream so prevent this

            foreach ($sourceDoc['ENTRIES'] as $entry) {

                if(isset($entry['PRIMARYDOCKEY']) && $entry['PRIMARYDOCKEY'] != '') {
                    $ok = false;
                    $gErr->addIAError('INV-0007', __FILE__ . ':' . __LINE__, 'Attempting to convert from a primary doc to another primary doc.', []);
                    break;
                }
            }

        }

        return $ok;
    }

    /**
     * @param array $oldDoc
     * @param array $currentDoc
     *
     * @return bool
     */
    private function validateDocument($oldDoc, $currentDoc)
    {
        $gErr = Globals::$g->gErr;
        $ok = true;
        
        $invInstalled = IsInstalled(Globals::$g->kINVid);

        // Parent Document
        $oldEntries = $oldDoc['ENTRIES'];
        $newEntries = $this->filterForNewEntries($oldDoc, $currentDoc);
        $inventoryConvert = $oldDoc['_DOCPAR']['SALE_PUR_TRANS'] == 'Internal';

        $nonInventoryItems = array(
            'Non-Inventory', 
            'Non-Inventory (Purchase only)',
            'Non-Inventory (Sales only)'
        );
        
        if (!$invInstalled) {
            $nonInventoryItems[] = 'Kit';
        }
        
        $sourceAffectsOnHand = '';

        foreach ($oldEntries as $oldEntry) {
            foreach ($newEntries as $newEntry) {
                if ($oldEntry['ITEMID'] == $newEntry['ITEMID']
                    && $oldEntry['RECORDNO'] == $newEntry['SOURCE_DOCLINEKEY']) {

                    if ($currentDoc['_DOCPAR']['UPDATES_INV'] != 'No'
                        && !in_array($oldEntry['ITEM']['ITEMTYPE'], $nonInventoryItems)

                    ) {
                        $sourceDate = $oldDoc['WHENCREATED'];

                        if (isset($newEntry['RECORDNO']) && $newEntry['RECORDNO'] != '') {
                            $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                                $newEntry['RECORDNO'], array('ITEMID' => $newEntry['ITEMID']), false
                            );
                            // $rec will be empty if any of the source documents is not
                            // affecting the OnHand (Quantity & Value / Value)
                            if (!empty($rec)) {
                                $sourceAffectsOnHand = true;
                                $sourceDate = $rec['DATEIN'];
                            }
                        }

                        if (
                            ($sourceAffectsOnHand || $oldEntry['ITEM']['ITEMTYPE'] == 'Kit')
                            && SysDateCompare(
                                $sourceDate, $currentDoc['WHENCREATED']
                            ) > 0
                            && !(in_array($currentDoc['STATE'], [DocumentManager::DRAFT_STATE, DocumentManager::ANALYZING_STATE ]))
                        ) {
                            $gErr->addIAError(
                                'INV-0320', __FILE__ . ':' . __LINE__,
                                sprintf('Source document date %1$s is greater than current document date %2$s', $sourceDate, $currentDoc['WHENCREATED']),
                                ['SOURCE_DATE' => $sourceDate,'CURRENT_DOC_WHENCREATED' => $currentDoc['WHENCREATED']]
                            );
                            $ok = false;

                        }
                    }
                    
                    if (!$inventoryConvert) {
                        $ok = $ok && $this->validateWarehouseChange($oldEntry, $newEntry);
                    }

                    if (in_array($oldEntry['ITEM']['ITEMTYPE'], $nonInventoryItems)) {
                        // only non-inventory items can have allocation set
                        // if allocation is set make sure the quantity is always 1 in both parent & child
                        $ok = $ok && $this->validateAllocationQtyForNewEntry($oldEntry, $newEntry, $currentDoc['_DOCPAR']);
                    }

                    $isDraft = (!empty($currentDoc['STATE'] ?? '')
                        && in_array($currentDoc['STATE'], [DocumentManager::DRAFT_STATE, DocumentManager::ANALYZING_STATE]));
                    $ok = $ok && $this->validateQtyConvertedForNewEntry($oldEntry, $newEntry, $isDraft);

                    if (!$ok) {
                        break;
                    }
                }
            }
        }
        return $ok;
    }

    /**
     * @param array $sourceEntry
     * @param array $newEntry
     *
     * @return bool
     */
    private function validateWarehouseChange($sourceEntry, $newEntry)
    {
        $ok = true;

        //
        // if any of the source documents in the workflow is affecting OnHand (Quantity & Value / Value)
        // changing the warehouse is not allowed
        $sourceAffectsOnHand = false;
        $sourceWhse = $sourceEntry['WAREHOUSE']['LOCATION_NO'];
        $newWhse = $newEntry['WAREHOUSE']['LOCATION_NO'];

        if ($sourceWhse != $newWhse) {
            if (isset($newEntry['RECORDNO']) && $newEntry['RECORDNO'] != '') {
                $rec = DocumentEntryCostManager::getParentDocentryCostDetail(
                    $newEntry['RECORDNO'], array('ITEMID' => $newEntry['ITEMID']), false
                );
                // $rec will be empty if any of the source documents is not affecting the OnHand (Quantity & Value / Value)
                $sourceAffectsOnHand = !empty($rec);
            }
        }

        if ($sourceAffectsOnHand) {
            $msg = sprintf('Changing the warehouse from \'%1$s\' to \'%2$s\' is not allowed when one of source documents is affecting On Hand inventory in the workflow.', $sourceWhse, $newWhse);
            $lineNo = 1 + $sourceEntry['LINE_NO'];
            $msg = sprintf('Failed to convert or update line %1$s, item \'%2$s\' from \'%3$s\'. %4$s', $lineNo, $sourceEntry['ITEMID'], $sourceEntry['DOCHDRID'], $msg);
            Globals::$g->gErr->addIAError(
                'INV-0334',
                 __FILE__ . ':' . __LINE__,
                 $msg, ['1_PLUS_SOURCE_ENTRY_LINE_NO' => $lineNo, 'SOURCE_ENTRY_ITEMID' => $sourceEntry['ITEMID'], 'SOURCE_ENTRY_DOCHDRID' => $sourceEntry['DOCHDRID'], 'SOURCE_WHSE' => $sourceWhse, 'NEW_WHSE' => $newWhse]
             );
            $ok = false;
        }

        return $ok;
    }

    /**
     * @param array $sourceEntry
     * @param array $newEntry
     *
     * @return bool
     */
    private function validateConversionTypeChange($sourceEntry, $newEntry)
    {
        $ok = true;

        // Treat a blank CONVERSIONTYPE as "Quantity" by default.
        $ctSource = $sourceEntry['CONVERSIONTYPE'];
        if ($ctSource == '') {
            $ctSource = 'Quantity';
        }
        if ($ctSource != $newEntry['CONVERSIONTYPE']) {
            $msg = sprintf('While converting %1$s, the conversion type changed to ', $sourceEntry['ITEMDESC']);
            if($newEntry['CONVERSIONTYPE'] === 'Price'){
                $msg .= 'Price.';
                $errorCode = 'INV-0321';
            }
            else{
                $msg .= 'Quantity.';
                $errorCode = 'INV-0322';
            }
            $correction = 'When converting a document, conversion types cannot be changed.';
            Globals::$g->gErr->addIAError(
                $errorCode,
                __FILE__ . ':' . __LINE__,
                $msg, ['ENTRY_ITEMDESC' => $sourceEntry['ITEMDESC']] ,
                $correction, []
            );
            $ok = false;
        }

        return $ok;
    }

    /**
     * @param array $sourceEntry
     * @param array $newEntry
     * @param bool $isDraft
     *
     * @return bool
     */
    private function validateQtyConvertedForNewEntry($sourceEntry, $newEntry, $isDraft)
    {
        // If the document is draft, we should ignore the validation.
        if($this->isReverseConversionLine($newEntry) || $isDraft){
            return  true ;
        }
        $msg = null;
        $qtyToConvert = self::getEntryConversionTypeQuantity($newEntry, $sourceEntry);

        if ($qtyToConvert != 0) {
            $qty = self::getEntryConversionTypeQuantity($sourceEntry);
            $qtyConverted = ( $sourceEntry[self::getConversionType_ConvertedValue($sourceEntry['CONVERSIONTYPE'])] ?? 0 );

            $signQty = ($qty < 0) ? -1 : 1;
            $signQtyToConvert = ($qtyToConvert < 0) ? -1 : 1;

            $placeHolder = [
                            'QTY_TO_CONVERT' => $qtyToConvert,
                            'SOURCE_ENTRY_ITEMID' => $sourceEntry['ITEMID'],
                            'SOURCE_ENTRY_DOCHDRID' => $sourceEntry['DOCHDRID'],
                            'QTY' => $qty
            ];
            if ($signQty != $signQtyToConvert) {
                $msg = "Quantity to convert ($qtyToConvert) is not the same sign as the original quantity ($qty)";
                $errorCode = 'INV-0466';
            } elseif ($qtyConverted != 0 && ($qtyConverted * $signQty >= $qty * $signQty)) { // Adding $qtyConverted != 0 to avoid initial state of item when it's 0
                $msg = "Trying to convert $qtyToConvert of an already converted line (quantity converted: $qtyConverted, original quantity: $qty)";
                $errorCode = 'INV-0467';
                $placeHolder = array_merge($placeHolder,['QTY_CONVERTED' => $qtyConverted]);
            }

            if ($msg) {
                $lineNo = 1 + $sourceEntry['LINE_NO'];
                $placeHolder = array_merge($placeHolder,['LINE_NO' => $lineNo]);
                $msg = "Failed to convert $qtyToConvert quantity of line $lineNo, item '${sourceEntry['ITEMID']}' of '${sourceEntry['DOCHDRID']}'. " . $msg;
                Globals::$g->gErr->addIAError($errorCode, __FILE__ . ':' . __LINE__, $msg, $placeHolder);
            }
        }
        return $msg === null;
    }

    /**
     * @param array $sourceEntry
     * @param array $newEntry
     * @param array $docpar
     *
     * @return bool
     */
    private function validateAllocationQtyForNewEntry($sourceEntry, $newEntry, $docpar)
    {
        // in cas eof PO documents there might be allocation used in newEntry
        // throw error if the Quantity of the sourceEntry is not 1
        // or the unit is different in newEntry
        if ($this->isInvalidQuantity($sourceEntry, $newEntry)) {
            $lineno = $newEntry['LINE_NO'] + 1;
            $msg = "Line#{$lineno} cannot be allocated because the quantity in the parent transaction is greater than 1 or the unit of measure is not same.";
            $msg .= " or the unit of measure is not same.";

            $desc1 = "To allocate the line, first change the quantity in the parent transaction to 1 and the unit as in the parent transaction and then convert the transaction again.";
            $desc1 .= " and the unit as in the parent transaction and then convert the transaction again.";

            Globals::$g->gErr->addIAError(
                'INV-0335', __FILE__ . ':' . __LINE__,
                $msg, ['LINENO' => $lineno],
                $desc1, []
            );

            return false;
        }

        //
        // dont allow to change the allocation in case of conversion
        // child must carry the same allocation as parent
        // if the document is created from XML GW chances are user may provide idfferent allocation
        // throw error if the allocation doesnt match with parent
        $docparID = $docpar['DOCID'];
        list($itemID) = explode('--', $newEntry['ITEMID']);
        $lineno = $newEntry['LINE_NO'] + 1;
        if ($sourceEntry['ALLOCATIONKEY'] != ''
            && $newEntry['ALLOCATIONKEY'] != $sourceEntry['ALLOCATIONKEY']
            && $newEntry['ALLOCATIONKEY'] != 0) {
            Globals::$g->gErr->addIAError(
                'INV-0323',
                __FILE__ . ':' . __LINE__,
                null, ['ITEMID' => $itemID, 'LINENO' => $lineno],
                null, ['DOCPARID' => $docparID]
            );

            return false;
        }

        return true;
    }

    /**
     * @param string[] $oldDoc
     * @param array    $currentDoc
     * @return array
     */
    private function filterForNewEntries($oldDoc, $currentDoc)
    {
        if (($currentDoc['CREATEDFROM'] ?? '') == $this->_multipleSourceDocsText) {
            $newEntries = [];
            $parentDocid = $oldDoc['DOCID'];
            // filter all the entries from this parent
            foreach ( $currentDoc['ENTRIES'] as $entry) {
                if ($parentDocid == $entry['SOURCE_DOCID']) {
                    $newEntries[] = $entry;
                }
            }
        } else {
            $newEntries = $currentDoc['ENTRIES'];
        }
        return $newEntries;
    }

    /**
     * in case of PO documents there might be allocation used in newEntry
     * throw error if the Quantity of the sourceEntry is not 1
     * or the unit is different in newEntry
     *
     * @param array $sourceEntry
     * @param array $targetEntry
     *
     * @return bool
     */
    private function isInvalidQuantity(array $sourceEntry, array $targetEntry) {
        $sourceRevisedUnitQty = $sourceEntry['REVISEDUNITQTY'] ?? "";
        if(Globals::$g->gManagerFactory->getManager('document')->isChangeOrderEnabled() && $sourceRevisedUnitQty !== "") {
            //we dont have the HASCHANGE flag set on entry level so we check using the REVISEDUNITQTY
            $sourceEntry['UIQTY'] = $sourceRevisedUnitQty;
        }

        if (isset($targetEntry['SOURCE_DOCLINEKEY']) && $targetEntry['SOURCE_DOCLINEKEY'] != ''
            && isset($targetEntry['ALLOCATIONKEY']) && $targetEntry['ALLOCATIONKEY'] !== ''
            && (isset($sourceEntry['UIQTY']) && $sourceEntry['UIQTY'] != 1
                || ($targetEntry['UIQTY'] == $sourceEntry['UIQTY']
                    && $targetEntry['UNIT'] != $sourceEntry['UNIT'])
            )
        ) {
            return true;
        }

        return false;
    }

    /**
     * check and return the entry quantity based on if any changeorder exists for the given doc
     *
     * @param array $entry
     * @param null|array $originalEntry
     *
     * @return string $quantity
     */
    private static function getEntryConversionTypeQuantity(array $entry, $originalEntry = null) {
        if ($originalEntry) {
            $conversionType = self::getConversionTypeSourceValue($originalEntry);
        } else {
            $conversionType = self::getConversionTypeSourceValue($entry);
        }
        $quantity = $entry[$conversionType] ?? 0;

        if (isset($entry['ISSUMMARIZED']) && $entry['ISSUMMARIZED'] == 'true') {
            $summaryBillDetailMgr = Globals::$g->gManagerFactory->getManager('summarybilleddetail');
            $summaryBillDetail = $summaryBillDetailMgr->getByDocEntryKey($entry['RECORDNO'], $originalEntry['RECORDNO']);
            if ($originalEntry['CONVERSIONTYPE'] == 'Price') {
                $quantity = $summaryBillDetail[0]['TXNPRICEBILLED'];
            } else {
                $quantity = $summaryBillDetail[0]['QUANTITYBILLED'];
            }
        } else {
            $revisedQuantity = $entry['REVISEDQTY'] ?? "";
            if ($conversionType === 'UIPRICE') {
                $revisedQuantity = $entry['REVISEDPRICE'] ?? "";
            } else if ($conversionType === 'TRX_PRICE') {
                $revisedQuantity = $entry['TRX_REVISEDPRICE'] ?? "";
            }
        }
        $isChangeOrderEnabled = Globals::$g->gManagerFactory->getManager('document')->isChangeOrderEnabled();

        if($isChangeOrderEnabled && !empty($revisedQuantity)) {
            $quantity = $revisedQuantity;
        }
        return $quantity;
    }

    /**
     * check and return the entry quantity based on if any changeorder exists for the given doc
     *
     * @param array $entry
     *
     * @return string $quantity
     */
    private static function getEntryQuantity(array $entry) {
        $quantity = $entry['QTY'] ?? 0;
        $revisedQuantity = $entry['REVISEDQTY'] ?? "";

        if(Globals::$g->gManagerFactory->getManager('document')->isChangeOrderEnabled() && $revisedQuantity !== "") {
            $quantity = $revisedQuantity;
        }
        return $quantity;
    }






    //  *********************************************************************************
    //  *********************************************************************************
    //
    //  Bulk Document Conversion
    //
    //  Here, we assume
    //  - You have a list of documents to convert
    //  - They have different document IDs and each has been configured in its TD to have one
    //      preferred target doc type
    //  - They should be saved ONE AT A TIME with transactions, so that some conversions may make it and
    //      some may not
    //  - You want to know, for each source doc id, what happened (errors) so you can report back to the user
    //
    //  This code is here because it seems like part of this class....
    //
    //  *********************************************************************************
    //  *********************************************************************************


    /**
     *      The root of bulk convert.
     *
     *      Pass in document IDs.
     *      Returned will be a single string of what happened per doc id, and whether it converted or not (or was a draft).
     *
     * Note: there is a TIME LIMIT on this.  We will stop after a certain amount of time has elapsed.
     *
     * @param string[]          $sourceDocIDs           Array of document ids, indexed by a key.  The key can be numeric or other;
     *                                                  ONE target document will be made for each of these entries, so you could, say,
     *                                                  have two docIDs but with a different key, for say, different ship-tos.
     * @param string[]          $converted              [returned] for each sourceDocID KEY, did it convert ('true', 'false', 'draft')?
     * @param string[]          $whatHappenedToThem     [returned] for each sourceDocID KEY, what happened?
     * @param bool              $inventoryFulfillmentOnly should this be for inventory fulfillment-->fulfillment
     * @param callable|null     $callForEachDocTree     (optional) called for each fetched source document
     *                                                  function(   $sourceDocID KEY,       the key you passed with the docid
     *                                                              $sourceDocID,           one of the source id's you passed in
     *                                                              $sourceDocType,         the underlying doc type ('Sales Order')
     *                                                              $targetDocType,         the chosen target doc type ('Shipper')
     *                                                              & $docTree,             the entire doc tree (from get() )
     *                                                                                          you can edit this if you wish
     *                                                              & $contextForCallback ) the context you passed in
     *                                                  returns '' or null if ok, text about the error if not ok
     *                                                  Use this to, say, edit the docentry records before we convert
     * @param array             $contextForCallback     (optional) passed to the callback doc
     *
     * @return bool                                     ok or catastrophic error (true returned even if one or more documents could not be saved)
     */
    public function bulkConvert($sourceDocIDs, & $converted, & $whatHappenedToThem, $inventoryFulfillmentOnly = false, callable $callForEachDocTree = null, $contextForCallback = null )
    {
        $errorCheckpoint        = Globals::$g->gErr->Checkpoint();
        $cache                  = $this->generateBulkConvertCache($sourceDocIDs, $inventoryFulfillmentOnly);
        $startTime              = microtime(true);       // how long does this take?
        $outOfTime              = false;
        $ok                     = true;

        // if we don't do this the FIRST convert may fail and be a draft but the SECOND succeeds!
        // so turn off warnings as much as possible
        $this->disableWarnings();   // so we fail consistently

        // for each doc id, convert it!
        foreach ($sourceDocIDs as $sourceDocKey => $sourceDocID) {

            // Heavens, is it THAT LATE already?  (we've taken too long)
            // let the remaining documents down gently.
            if ($outOfTime) {
                $converted[$sourceDocKey]          = 'false';
                $whatHappenedToThem[$sourceDocKey] = _("Maximum processing time expired.  Select fewer documents and try again.");
                continue;
            }

            // are there underlying problems?
            if ($cache[$sourceDocID]['CONVERTABLE'] === false) {
                $converted[$sourceDocKey]          = 'false';
                $whatHappenedToThem[$sourceDocKey] = $cache[$sourceDocID]['WHATHAPPENED']; // the ID is for the whole doc, the KEY is for this instance
                continue;
            }

            // get a document manager for the source.  No need for forcenew, that's for the target
            // supplying the docparid means we get custom fields and relationships and the like
            /** @var DocumentManager $docMgrForSource */
            $docMgrForSource = Globals::$g->gManagerFactory->getManager($cache[$sourceDocID]['MANAGER'],
                false, ['DOCTYPE' => $cache[$sourceDocID]['DOCPARID']] );

            $documentTree  = $docMgrForSource->Get($sourceDocID);
            if (($documentTree === null) || ($documentTree === false) || empty($documentTree)) {
                $converted[$sourceDocKey]          = 'false';
                $whatHappenedToThem[$sourceDocKey] = $cache[$sourceDocID]['WHATHAPPENED'];
                continue;
            }

            if ( ! $this->prepareDocument($documentTree, $cache[$sourceDocID])) {
                continue;
            }

            // see if the client wants to edit the doc tree
            if ($callForEachDocTree !== null) {
                $whatHappened = $callForEachDocTree($sourceDocKey, $sourceDocID,
                                    $cache[$sourceDocID]['DOCPARID'],  $cache[$sourceDocID]['TARGETDOCPARID'],
                                    $documentTree, $contextForCallback);
                if (($whatHappened !== null) && ($whatHappened != '')) {
                    $converted[$sourceDocKey]          = 'false';
                    $whatHappenedToThem[$sourceDocKey] = $whatHappened;
                    continue;
                }
            }

            // get a fresh, new document manager with the right td of the TARGET
            /** @var DocumentManager $docMgrForTarget */
            $docMgrForTarget = Globals::$g->gManagerFactory->getManager($cache[$sourceDocID]['MANAGER'],
                true, ['DOCTYPE' => $cache[$sourceDocID]['TARGETDOCPARID']] );

            // Convert!  (Go get a cup of coffee....)
            $this->bulkConvertOneDocument( $documentTree,
                                            $docMgrForTarget,
                                            $convertedThisOne,
                                            $whatHappened);
            $converted[$sourceDocKey]          = $convertedThisOne;
            $whatHappenedToThem[$sourceDocKey] = $whatHappened;

            Globals::$g->gErr->Restore($errorCheckpoint);   // reset the error table back to what it was before we called this.

            $outOfTime = ((microtime(true) - $startTime) > self::MAX_TASK_TIME);

            if ( ! $ok) {
                break;      // this is a problem not just for one transaction but for the whole shebang
            }
        }
        return $ok;
    }


    /**
     *  disable warnings: do what CSV and the API does: turn off warnings as warnings, make them all errors.
     *          we may still go to DRAFT, but not post.
     */
    private function disableWarnings()
    {
        $entity = ( $this->_mod === 'po' ) ? 'apbill' : 'arinvoice';    // guessing we don't care about inv????
        /** @var SubLedgerTxnManager|ARInvoiceManager $trxManager */
        $trxManager = Globals::$g->gManagerFactory->getManager($entity);
        $trxManager->setShowWarningsAsErrorsAlways(true);
    }


    /**
     *  Do any preparation of the FROM document to turn it into a TO document.
     *
     * @param array             $documentTree           Document
     * @param array             $cache                  The cache we set up earlier
     *
     * @return  bool                    Are we good?
     */
    private function prepareDocument( & $documentTree, $cache)
    {

        $targetDocParID = $cache['TARGETDOCPARID'];     // target document type ('Shipper')
        $docpar         = $cache['DOCPAR'];
        $docId          = $cache['DOCID'];
        $sourceDocKey   = $documentTree['RECORDNO'];

        $documentTree['CREATEDFROM'] = $docId;
        $documentTree['DOCPARID']    = $targetDocParID;
        $documentTree['DOCPARKEY']   = $docpar['RECORDNO']; // target's record number
        $documentTree['_DOCPAR']     = $docpar;
        $documentTree['_mod']        = $cache['MOD'];
        $documentTree['WHENCREATED'] = GetCurrentDate();    // AUWHENCREATED is handled by document manager
        unset($documentTree['RECORDNO'], $documentTree['DOCID'], $documentTree['STATE']);

        // Default due date when there is a term, otherwise bail
        // Looks like DocumentManager handles this....
        $documentTree['WHENDUE'] = '';

        // now handle the entries
        foreach ($documentTree['ENTRIES'] as $index => $row) {

            $docEntryKey                                            = $row['RECORDNO'] ?? 0;  // the FROM record#
            $documentTree['ENTRIES'][$index]['SOURCE_DOCID']        = $docId;
            $documentTree['ENTRIES'][$index]['SOURCE_DOCLINEKEY']   = $docEntryKey;
            $documentTree['ENTRIES'][$index]['SOURCE_DOCKEY']       = $sourceDocKey;

            // clear things out
            unset(  $documentTree['ENTRIES'][$index]['PRRECORDKEY'],
                $documentTree['ENTRIES'][$index]['PRINVBATCHKEY'],
                $documentTree['ENTRIES'][$index]['ADDGLBATCHKEY'],
                $documentTree['ENTRIES'][$index]['RECORDNO'],
                $documentTree['ENTRIES'][$index]['RECORD#']);

            // clear out tracking
            if (isset( $documentTree['ENTRIES'][$index]['TRACKINGENTRIES'])) {
                foreach ($documentTree['ENTRIES'][$index]['TRACKINGENTRIES'] as $trackIndex => $trackRow) {
                    unset($trackRow['WORKQUEUEKEY'], $trackRow['RECORDNO'], $trackRow['RECORD#'], $trackRow['DOCENTRYNO']);
                    $documentTree['ENTRIES'][$index]['TRACKINGENTRIES'][$trackIndex] = $trackRow;
                }
            }
        }
        return true;
    }


    /**
     *      To make things work without hundreds of sql queries in overhead, try to pre-compute
     *  what we need for the bulk conversions.  Granted, the conversions themselves will take
     *  forever, but at least that won't be my fault!
     *
     * @param string[]      $sourceDocIDs               what we want to convert
     * @param bool          $inventoryFulfillmentOnly   should we ONLY include Inventory Fulfillment TDs?
     *
     * @return array                                    the cache
     */
    private function generateBulkConvertCache($sourceDocIDs, $inventoryFulfillmentOnly)
    {
        $errorCheckpoint    = Globals::$g->gErr->Checkpoint();
        $cache              = [];

        $docMgr = Globals::$g->gManagerFactory->getManager('document');
        $qry    = array(
            'selects' => array('DOCID', 'STATE', 'DOCPARID', 'DOCPARKEY', 'RECORDNO'),
            'filters' => array(array( array('DOCID', 'IN', $sourceDocIDs))),
            'usemst' => true,
        );
        $sourceDocStuff = $docMgr->GetList($qry);

        $docParIds = [];
        foreach ($sourceDocStuff as $row) {
            $docId = $row['DOCID'];
            $ok = self::isDocumentConvertable($docId, $row['STATE']);
            $cache[$docId] = $row;
            $docParIds[$row['DOCPARID']] = true;
            if ($ok) {
                $cache[$docId]['CONVERTABLE']  = true;
                $cache[$docId]['WHATHAPPENED'] = '';
            } else {
                $cache[$docId]['CONVERTABLE']  = false;
                $cache[$docId]['WHATHAPPENED'] = Globals::$g->gErr->myToString(true, 20 );
                Globals::$g->gErr->Restore($errorCheckpoint);
                // BUT KEEP GOING
            }
        }

        // next, find the target docid to convert to for each document....
        $graph = $this->bulkConvertTo(array_keys($docParIds), $inventoryFulfillmentOnly );

        $docparMgr = null;
        $lastMod   = '';
        foreach ($docParIds as $docParId => $yes) {
            // simple for now....
            $docParIds[$docParId]                   = [];
            $graphForThisDocPar                     = $graph[$docParId];
            $targetDocParId                         = $graphForThisDocPar['BULK'] ?? '';
            $mod                                    = $this->_mod;
            $docParIds[$docParId]['TARGETDOCPARID'] = $targetDocParId;
            $docParIds[$docParId]['MOD']            = $mod;
            $docParIds[$docParId]['MANAGER']        = $mod . 'document';

            // we need the right docpar manager for the module.  Is this one the same as the last pass?
            // I'm guessing MOST bulk converts are all for the same module, like SO or PO, but just in case.....
            if (($docparMgr === null) || ($mod !== $lastMod)) {
                $lastMod   = $mod;
                $docparMgr = Globals::$g->gManagerFactory->getManager($mod . 'documentparams');
            }
            $docParIds[$docParId]['DOCPAR'] = ($targetDocParId != '') ? $docparMgr->GetLatest($targetDocParId, false) : null;
        }

        // set the targets for each docid
        foreach ($cache as $docId => $row) {
            $docParId                           = $row['DOCPARID'];
            $cache[$docId]['TARGETDOCPARID']    = $docParIds[$docParId]['TARGETDOCPARID'];
            $cache[$docId]['MANAGER']           = $docParIds[$docParId]['MANAGER'];
            $cache[$docId]['MOD']               = $docParIds[$docParId]['MOD'];
            $docpar                             = $docParIds[$docParId]['DOCPAR'];
            $error                              = $docParIds[$docParId]['ERROR'] ?? '';
            $tokens = [
                ['id' => 'IA.DONT_HAVE_PERMISSION_TO_CONVERT'],
                ['id' => 'IA.THE_TARGET_DOCUMENT_TYPE_IS_INACTIVE']
            ];
            $text = getLocalizedTextWithThrow($tokens);
            if (($docpar === null) || ($error != '')) {
                $cache[$docId]['CONVERTABLE']  = false;
                if ($error == '') {
                    $error = $graph[$docParId]['ERROR'] ?? '';
                }
                $cache[$docId]['WHATHAPPENED'] = ($error != '') ? $error : GT($text,'IA.DONT_HAVE_PERMISSION_TO_CONVERT');
            } else if ($docpar['STATUS'] === 'inactive') {
                $cache[$docId]['CONVERTABLE']  = false;
                $cache[$docId]['WHATHAPPENED'] = GT($text,'IA.THE_TARGET_DOCUMENT_TYPE_IS_INACTIVE');
            } else {
                $cache[$docId]['DOCPAR'] = $docpar;
            }
        }
        return $cache;
    }


    /**
     *      While bulk converting, try converting just ONE document.  We're in a transaction from the parent,
     *  so it is safe to just return true/false when you want.
     *
     * @param array             $documentTree       what get() returned for the ORIGINAL document
     * @param DocumentManager   $targetManager      target document manager
     * @param string            $converted          [returned] did it convert ('true', 'false', 'draft')?
     * @param string            $whatHappened       [returned] what happened? (English)
     *
     * @return bool         Did this work?  (not catastrophic, just for this one doc)
     */
    private function bulkConvertOneDocument($documentTree, $targetManager, & $converted, & $whatHappened)
    {
        $source         = 'bulkConvertOneDocument';

        // anything else to do?
        // note that 'add()' does its own transaction management
        $errorCheckpoint            = Globals::$g->gErr->Checkpoint();
        $converted                  = 'true'; // hopefully
        $originalError              = '';

        try {
            $ok = $targetManager->beginTrx($source);
            $ok = $ok && $targetManager->add($documentTree);
            if ($ok === true) {
                $tokens = [
                    [
                        'id' => 'IA.CONVERTED_TO',
                        'placeHolders' => [
                            ['name' => 'DOC', 'value' => $documentTree['DOCID']]
                        ]
                    ]
                ];
                $text_map = getLocalizedTextWithThrow($tokens);
                $whatHappened = GT($text_map,'IA.CONVERTED_TO');
            } else {
                // todo: any simple checks to avoid trying to save as a draft?
                $converted     = 'draft'; // hopefully
                $originalError = Globals::$g->gErr->myToString(true, 20 );
                $whatHappened  = $originalError;
                Globals::$g->gErr->Restore($errorCheckpoint);
                $documentTree['STATE'] = BasePRRecordManager::DRAFT_STATE;
                $targetManager->rollbackTrx($source);
                $ok = $targetManager->beginTrx($source);
                $ok = $ok && $targetManager->add($documentTree); // try again
                if ($ok === true) {
                    // remove two common, excessive, messages as per DE24710
                    $whatHappened = str_replace( _("Error preparing values"), "", $whatHappened);
                    $whatHappened = str_replace( _("Could not create Document record"), "", $whatHappened);
                    $whatHappened = sprintf(_("Converted to %1s as a DRAFT document.  You must manually POST the document.  %2s"),
                        $documentTree['DOCID'], $whatHappened);
                }
            }
        } catch (Exception $e) {
            $ok = false;
            $whatHappened = _("Unable to post because: ") . $e->getMessage();
        }

        if (($ok === false) || (! Globals::$g->gErr->isEmpty())) {
            $whatHappened = Globals::$g->gErr->myToString(true, 20 );
            if ($whatHappened == '') {
                $whatHappened =  $originalError;
            }
            $converted    = 'false';
            $ok           = false;
        }

        $ok = $ok && $targetManager->commitTrx($source);
        if (!$ok) {
            $targetManager->rollbackTrx($source);
        }

        return $ok;
    }

    /**
     * @param $entry
     * @param $newentry
     *
     * @return void
     */
    private function prepareReverseConversionFieldValues(&$entry, $newentry, $delete){
        $isReverseConversionEnabled = $this->isReverseConversionEnabled;
        $newValue = $this->getEntryConversionTypeQuantity($newentry, $entry);
        $conversionTypeLabel = self::getConversionType_ConvertedValue($entry['CONVERSIONTYPE']);

        $stdConvertedFieldType = $this->getStandardConversionFieldType($conversionTypeLabel);
        $reverseConvertedFieldType = $this->getReverseConversionFieldType($conversionTypeLabel);

        $isReverseConversionLine = $this->isReverseConversionLine($newentry);

        if ($delete) {
            if($isReverseConversionLine){
                $entry[$reverseConvertedFieldType] = ibcsub(
                    $entry[$reverseConvertedFieldType], $newValue, ItemManager::BASEUNITPRECISION
                );
            }else{
                $entry[$stdConvertedFieldType] = ibcsub(
                    $entry[$stdConvertedFieldType], $newValue, ItemManager::BASEUNITPRECISION
                );
            }
        } else {

            if($isReverseConversionLine){
                $entry[$reverseConvertedFieldType] = ibcadd(
                    $entry[$reverseConvertedFieldType], $newValue, ItemManager::BASEUNITPRECISION
                );
            }else{
                $entry[$stdConvertedFieldType] = ibcadd(
                    $entry[$stdConvertedFieldType], $newValue, ItemManager::BASEUNITPRECISION
                );
            }
        }

        if ($entry['CONVERSIONTYPE'] == "Price") {
            $stdQtyConvertedField = $this->getStandardConversionFieldType('QTY_CONVERTED');
            $entry[$stdQtyConvertedField] = 0;
            if($isReverseConversionLine){
                $reverseQtyConvertedField = $this->getReverseConversionFieldType('QTY_CONVERTED');
                $entry[$reverseQtyConvertedField] = 0;
            }
        }

        if($isReverseConversionEnabled && $isReverseConversionLine){
            $entry["REVERSECONVERSION"] = $newentry['REVERSECONVERSION'];
        }
    }

    /**
     * @param string $conversionType
     *
     * @return string
     */
    private function getStandardConversionFieldType($conversionType) {
        return $conversionType == "QTY_CONVERTED" ? "STDQTYCONVERTED" : "STDPRICECONVERTED";
    }

    /**
     * @param string $conversionType
     *
     * @return string
     */
    private function getReverseConversionFieldType($conversionType){
        return $conversionType == "QTY_CONVERTED" ? "REVERSEQTYCONVERTED" : "REVERSEPRICECONVERTED";
    }

    /**
     * @param array $value
     *
     * @return bool
     */
    private function isReverseConversionLine($value){
        if(CRESetupManager::isReverseConversionEnabled() &&!empty($value["REVERSECONVERSION"]) && $value["REVERSECONVERSION"] == "true"){
            return true;
        }
        return false;
    }

    /**
     * @param array $enties
     *
     * @return bool
     */
    private function isReverseConversionLineExist($enties){

        foreach ($enties as $entry){
            if($this->isReverseConversionLine($entry)){
                return true;
            }
        }
        return false;

    }

    /**
     * @param array|string $doc
     *
     * @return string|null
     */
    private function getModuleType($doc)
    {
        $transType = null;
        if(!empty($doc['_DOCPAR']['SALE_PUR_TRANS'])){
            $transType = $doc['_DOCPAR']['SALE_PUR_TRANS'];
        }else{
            if(is_array($doc)){
                $docId = $doc['DOCID'];
            }else{
                $docId = $doc;
            }
            if(!empty($this->moduleType[$docId])){
                $docMgr = Globals::$g->gManagerFactory->getManager('document');
                $params = [
                    'selects' => ['SALE_PUR_TRANS'],
                    'filters' =>[[[ 'DOCID', '=', $docId ],],],
                ];
                $resultSet = $docMgr->GetList($params);
                if(!empty($resultSet[0])){
                    $transType = $resultSet[0]['SALE_PUR_TRANS'];
                }else{
                    $transType =  "";
                }
                $this->moduleType[$docId] = $transType;
            }
            $transType = $this->moduleType[$docId];
        }

        if( $transType === "Purchase" ){
            return 'po';
        }elseif($transType === "Sale"){
            return 'so';
        }
        return null;
    }

    /**
     * @param $doc
     *
     * @return bool
     * @throws Exception
     */
    private function isReverseConversionAllowed($doc){
        $mod = $this->getModuleType($doc);
        if(!empty($mod)){
            $docMgr = Globals::$g->gManagerFactory->getManager('document');
            return $docMgr->isReverseConversionAllowed($mod);
        }
        return false;
    }


}
