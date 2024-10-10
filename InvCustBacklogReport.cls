<?
import('InventoryCustVendReporter');
require_once 'Dictionary.cls';

/**
 * Class InvCustBacklogReport
 */
class InvCustBacklogReport extends InventoryCustVendReporter
{
    /**
     * @param array $params
     */
    public function __construct($params)
    {
        $params['whereclause']['cust'] = " (upper(docpar.docclass) = 'ORDER' AND 
											upper(docpar.sale_pur_trans) = 'S' AND
											upper(dochdr.state) in ('O','P','B')
											AND EXISTS (SELECT 1 FROM docpartotals dpt 
                                                        INNER JOIN ictotal ict ON upper(ict.cny#) = upper(dpt.cny#) AND upper(ict.record#) = upper(dpt.totalkey)  
                                                        WHERE 
                                                        upper(dpt.cny#) = upper(docpar.cny#) AND 
                                                        upper(dpt.docparkey) = upper(docpar.record#) AND 
                                                        upper(ict.name) = 'ONHOLD' AND upper(dpt.sign) = 1)
											)";

        parent::__construct(
            INTACCTarray_merge(
                $params,
                array(    
                'ops' => array(
                                    'so/lists/customer/view',
                                    'so/lists/sodocument/view',
                                    'so/lists/item/view',
                                    ),
                'reportslide' => true,
                'report'    => 'invbacklog',
                'custvend'     => 'cust',
                'reportby'     => 'cust'
                )
            ) 
        );
    }

    /**
     * @return bool
     */
    function DoQuery()
    {
        if (!$this->ValidateReport()) {
            return false;
        }

        $this->params['safe']['FILTERTRANSACTIONS'] = $this->params['FILTERTRANSACTIONS'];
        $params = $this->params['safe'];

        $fromitemid = $params['FROMITEMID'];
        $toitemid = $params['TOITEMID'];
        $fromcustid = $params['FROMCUSTOMERID'];
        $tocustid = $params['TOCUSTOMERID'];
        //$fromvendorid = $params['FROMVENDORID'];
        //$tovendorid = $params['TOVENDORID'];
        $dt1 = $params['dt1'];
        $dt2 = $params['dt2'];

        $ReportOn = $this->params['REPORTON'];
        $fromupc = $params['FROMUPC'];
        $toupc = $params['TOUPC'];
        $ItemOperator = $this->params['ITEMOPERATOR'];
        $itemValues = $this->params['ITEMVALUES'];
        $UPCOperator = $this->params['UPCOPERATOR'];
        $upcValues = $this->params['UPCVALUES'];

        $cny = GetMyCompany();

        $filterlocation = $this->_getLocationClause($params, 'docentry');
        $filterdept = $this->_getDeptClause($params, 'docentry');

        $whereclause = $this->params['whereclause'][$this->params['custvend']];
        $datefilter = $this->params['whereclause']['datefilter'];

        $args = array('sql', $cny,); //$fromitemid, $toitemid, $dt1, $dt2, $fromcustvendid, $tocustvendid);

        if ($ReportOn == 'ITEMID') {
            if ($fromitemid == VARCHAR2_MIN && $toitemid == VARCHAR2_MAX && $itemValues != '') {

                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $ItemOperator, 'icitem', 'itemid', $itemValues, 2);
                // itemupcargs will be blank in case of include/excludes operator
                //if( $itemupcargs !=''){
                array_push($args, $itemupcargs, '');
                //}

            } else {
                $filterItemorUPC = " icitem.itemid  >= :2 and icitem.itemid  <= :3 ";
                array_push($args, $fromitemid, $toitemid);
            }
            $orderBy = "itemkey";
        } else {

            if ($fromupc == VARCHAR2_MIN && $toupc == VARCHAR2_MAX && $upcValues != '') {
                $this->GetFilterArgs($filterItemorUPC, $itemupcargs, $UPCOperator, 'icitem', 'upc', $upcValues, 2);
                // itemupcargs will be blank in case of include/excludes operator
                //if( $itemupcargs !=''){
                array_push($args, $itemupcargs, '');
                //}
            } else {
                $filterItemorUPC = " icitem.upc  >= :2 and icitem.upc  <= :3 ";
                array_push($args, $fromupc, $toupc);
            }

            $orderBy = "upc";
        }

        $selectmcp = "";
        $currencyfilter = "";

        if ($this->params['custvend'] == 'vend') {
            $casewhen_convertbyline = '';
        } else {
            $casewhen_convertbyline = $this->params['whereclause']['licselect'];
            $casewhen_convertbyline = ($casewhen_convertbyline != '') ? $casewhen_convertbyline : '';

        }

        if ($this->_ismcpEnabled) {
            $baseCurrency = GetBaseCurrency();
            $selectmcp = ", docentry.currency,
							CASE WHEN (dochdr.state='P' $casewhen_convertbyline) THEN
								round(((docentry.quantity - docentry.qty_converted)*(docentry.price / nvl(docentry.exchange_rate,1))),3)
							ELSE
                                docentry.trx_value
							END trx_value,
							((docentry.uiqty*docentry.trx_price) / docentry.quantity) trxprice";
            //$selectmcp = ", docentry.currency, (docentry.uiqty * docentry.trx_price) trxprice, docentry.trx_value";
            if ($this->params['CURRENCY'] != '') {
                //$currencyfilter = ($currency!='') ? " and docentry.currency='".$currency."'" : "";
                $currencyfilter = " and DECODE(docentry.currency, NULL, '$baseCurrency', docentry.currency) = '" . $this->params['CURRENCY'] . "'";
            }
        }


        $LICfilter = $this->params['whereclause']['licfilter'];
        $LICfilter = ($LICfilter != '') ? $LICfilter : '';

        $qryselect = "SELECT
							customer.customerid as id,
							customer.name as name,
							customer.locationkey as ENOWNERLOC,
							dochdr.docno,
							dochdr.docid,
							dochdr.whencreated,
							dochdr.whendue,
							dochdr.melocationkey,
							dochdr.record# as hdrrec,
							to_char(to_date(dochdr.whendue)-SYSDATE,'9999999') as daystodue,
							icitem.itemid as itemkey,
							icitem.locationkey as ITOWNERLOC,
							icitem.name as itemdescr,
							docentry.dochdrkey,
							CASE WHEN (dochdr.state='P' $casewhen_convertbyline) THEN
                                docentry.quantity - docentry.qty_converted
                            ELSE
                                docentry.quantity
                            END quantity,
							docentry.price,
							CASE WHEN (dochdr.state='P' $casewhen_convertbyline) THEN
								(docentry.quantity - docentry.qty_converted)*docentry.price
							ELSE
								(docentry.quantity*docentry.price)
                            END value,
							icitem.upc $selectmcp
						FROM docentry, docpar, dochdr, customer, icitem
						WHERE
							icitem.cny# = :1 and
							" . $filterItemorUPC . " and
							----
							docentry.cny# = icitem.cny# and
							docentry.itemkey = icitem.itemid and
							--
							docentry.dochdrkey = dochdr.record# and
							docentry.cny# = dochdr.cny# and
							docentry.quantity != 0 and
							$LICfilter
							((docentry.quantity != docentry.qty_converted and dochdr.state='P') or dochdr.state in ('O','C','D', 'L', 'B')) and
							--- external datefilter contains :4 and :5
							" . $datefilter . "
							---
							dochdr.custentity = customer.entity and
							customer.cny# = dochdr.cny# and
							customer.customerid >= :6 and
							customer.customerid <= :7 and
							---
							dochdr.docparkey = docpar.record# and
							dochdr.cny# = docpar.cny# and
							
							--external where section
							$whereclause $filterdept $filterlocation $currencyfilter 
							
							-- end external where
						ORDER BY docno, $orderBy, id, dochdrkey";
        $fromcustvendid = $fromcustid;
        $tocustvendid = $tocustid;

        array_push($args, $dt1, $dt2, $fromcustvendid, $tocustvendid);
        $args[0] = $qryselect;

        //$this->_itemlist = QueryResult(array($qryselect, $cny, $fromitemid, $toitemid, $dt1, $dt2, $fromcustvendid, $tocustvendid));
        $this->_itemlist = QueryResult($args);
        return true;
    }
}

