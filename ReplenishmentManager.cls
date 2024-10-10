<?php /** @noinspection ArgumentEqualsDefaultValueInspection */
/** @noinspection NestedPositiveIfStatementsInspection */
/**
 * Manager file for the standard object replenishment
 *
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation All, Rights Reserved
 */




require_once 'backend_prrecord.inc';


/**
 * ReplenishmentManager Doc Comment
 *
 * @category  Cls
 * @package   Source/inventory
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation, All Rights Reserved
 */
class ReplenishmentManager extends EntityManager
{
        // what are we doing?
    const GENERATE_SNAPSHOT          = 'GenSnap';
    const GENERATE_POS               = 'GenPOs';

    const TIME_LIMIT_SECONDS         = (60.0 * 3); // 3 minutes; that allows some more time to fetch prices and such.

    const ON_OR_BEFORE_NOW           = "<=";
    const AFTER_NOW                  = ">";

    const WAREHOUSE_PLACEHOLDER      = '--';    // so we're not comparing a warehouse id with empty strings, potentially causing troubles.

    const MAX_ERROR_LENGTH           = 2000;  // current limit of the database field 'ERROR_MESSAGE'




    /**
     * @var array $inventoryPrefs    inventory preferences
     */
    private     $inventoryPrefs = array();


    /**
     * @var string[] $filters        all the filters we understand
     */
    private     $filters;


    /**
     * @var array $sqlTables           all the sql tables that we use to generate queries
     */
    private     $sqlTables;

    /**
     * @var string[] $tableTimePeriod    does the query act AFTER the as-of date, or ON-OR-BEFORE?
     */
    private     $tableTimePeriod;

    /**
     * @var string[][] $joins   how to join tables
     */
    private     $joins;

    /**
     * @var string[] $tableGroups   groups of sql tables queried together
     */
    private     $tableGroups;

    /**
     * @var string[] $groupBy    any 'GROUP BY' clauses for tables.
     */
    private     $groupBy;

    /**
     * @var string[] $orderBy      how to sort the records
     */
    private     $orderBy;

    /**
     * @var ReplenishDetailManager $replenishDetailMgr
     */
    private     $replenishDetailMgr;

    /**
     * @var contactManager $contactMgr
     */
    private     $contactMgr;

    /**
     * @var string[] $docpar     the DOCPAR record for the given PO transaction
     */
    private     $docpar;

    /**
     * @var PricingHandler  $pricingHandler
     */
    private     $pricingHandler;

    /**
     * @var ExchangeRateManager     $exchMgr
     */
    private     $exchMgr;

    /**
     * @var PODocumentManager       $podocumentMgr
     */
    private     $podocumentMgr;

    /**
     * @var array $kitPartInformation  for each kit PART, what kits (itemID) do they belong to?  what Quantity do we need in BASE UNITS?
     */
    private     $kitPartInformation = array();

    /**
     * @var int[] $longestLeadTime  the list of 'longest lead times' for items' vendors, or -1 if we haven't seen an item's vendors yet.
     */
    private     $longestLeadTime = array();     // -1 means we haven't seen any vendors for the item

    /**
     * @var array $kitInfo                 index is the kits itemId
     */
    private     $kitInfo = array();                // the kits in the list, with JUST kit item info, no vendors (there aren't any) and maybe warehouse info

    /**
     * @var array $UOMGroups  list of UOM Groups, indexed by UOM record# (because that's what the item table stores)
     */
    private     $UOMGroups = array();

    /**
     * @var array $forecastTableEntries
     */
    private     $forecastTableEntries = null;

    /**
     * @var array $parametersStack
     */
    private     $parametersStack = array();     // a stack of parameter values so we can push/pop them

    /**
     * @var string[]  $locationCache
     */
    private     $locationCache = array();       // array of name => record number

    /**
     * @var int $currencyExchangeID         the ID of the exchange we should use.  -1 is 'Intacct Daily Rate'
     */
    private     $currencyExchangeID = INTACCT_RATE_ID;

    /**
     * @var string $currencyExchangeName    the name of the exchange we should use, like 'MXN-exchange'
     */
    private     $currencyExchangeName = INTACCT_RATE;

    /**
     * @var string $deliverToHeader         the 'DELIVER-TO' default header for all POs.
     */
    private     $deliverToHeader = '';

    /**
     * @var bool $deliverToLine           DO we allow line-level DELIVER-TO?
     */
    private     $deliverToLine = false;

    /** @var float[][] $uomCache */
    private     $uomCache = array();

    /** @var string $myLocationName  */
    private     $myLocationName = "";

    /** @var int $defaultPrecisionForPO */
    private     $defaultPrecisionForPO = 8;

    /** @var string $diagnostics */
    private     $diagnostics = "";



    /**
     * Constructor
     *
     * @param string[]  $params List of parameters for specific to this object
     *
     */
    function __construct($params = array())
    {
        $this->inventoryPrefs = array();
        GetModulePreferences(Globals::$g->kINVid, $this->inventoryPrefs);

        $poPrefs = array();
        GetModulePreferences(Globals::$g->kPOid, $poPrefs);
        $this->defaultPrecisionForPO = (int)($poPrefs['ITEMPRECISION'] ?? 8);

        // we aren't a document, but we want document treatment for things like custom dimensions....
        $this->_docType = $params['TRANSACTION_DEFINITION'];    // enables magic in the entity manager :-(
        if ($this->_docType == '') {
            // we need SOME transaction definition in order to get custom dimensions.  If we didn't get one from the caller,
            // use the default one in preferences, if available.  If may not be the one we evenually use, but all we need
            // is SOME TD to get the custom dimensions :-(
            $this->_docType = $this->inventoryPrefs['DEFAULT_PURCHASE_TRANSACTION'];
            $params['TRANSACTION_DEFINITION'] = $this->_docType;
        }

        parent::__construct($params);


        //  *************************************************************************
        //  *************************************************************************
        //
        //  Queries
        //
        //      Most of the queries I need for this report can be built out of
        //  common stuff, and so I made this table-driven approach here.
        //
        //      filters is the name of the various filters I support
        //
        //      tables lists, for each sql table, what it's 'shorthand' name is (as in
        //          "FROM ICITEM i,", and the fields that represent the filters
        //          like 'FILTER_VENDORID' is the vendorid field in the 'VENDOR' file.
        //          Also a list of common fields to get.  Sometimes, the file name too
        //          when that differs from the main key (so we can have two views on one file)
        //
        //      joins are the 'standard' WHERE clause items for the given file,
        //          like connecting the CNY# and the 'normal' filtering.  Added to these
        //          will be any FILTER_XXXXX items, or potentially, custom items.
        //
        //      file-groups are the set of tables needed for a specific query.
        //          like if you need icitem and icwarehouse, a group would mention both of them.
        //
        //      group-by is the list of tables that need a gropup-by in them; this is unusual,
        //          but...
        //
        //  *************************************************************************
        //  *************************************************************************

            // These are all the filters we know about and obey.....
        $this->filters = array(
            'FILTER_ASOFDATE',
            'FILTER_VENDORID',
            'FILTER_VENDOR_TYPE',
            'FILTER_WAREHOUSE',
            'FILTER_PRODUCTLINEID',
            'FILTER_ITEM',
            'FILTER_CURRENCY',
            'FILTER_LOCATIONKEY',   // NOTE: WE CARE ABOUT THE WAREHOUSE LOCATION KEY ABOVE OTHERS

            'FILTER_VENDORGROUP',
            'FILTER_ITEMGROUP', // derived from FILTER_ITEM
            'FILTER_WAREHOUSEGROUP',
            // 'FILTER_LOCATIONKEYGROUP', seems harder because the location is already a list of locations (specified one plus all children)
        );

            // This shows for each file we use the 'shorthand' (like i in FROM icitem i) and the field names for the filters
        $this->sqlTables = array(

             'VENDOR'                => array( 'FILE_SHORTHAND' => 'v',  'FILTER_VENDORID' => 'vendorid', 'FILTER_CURRENCY' => 'CURRENCY', 'FILTER_VENDORGROUP' => 'record#',
                                                'FIELDS' => array(
                                                    'v.record#                         as VENDORDIMKEY',
                                                    'v.vendorid                        as VENDOR',
                                                    'v.currency                        as CURRENCY',
                                                    'v.name                            as VENDORNAME',
                                                    'v.default_lead_time               as V_LEAD_TIME',
                                                    'v.termskey                        as V_TERMSKEY',
                                                    'v.FORM1099TYPE',
                                                    'v.FORM1099BOX',
                                                )
                                            ),
            'VENDTYPE'              => array( 'FILE_SHORTHAND' => 'vt', 'FILTER_VENDOR_TYPE' => 'name'), // vendtypekey in vendor
            'TERM'                  => array( 'FILE_SHORTHAND' => 't',
                                                'FIELDS' => array(
                                                    't.record#                         as TERM_RECORDNO',
                                                    't.name                            as TERMSNAME',
                                                )
                                            ),
            'ICWAREHOUSE'           => array( 'FILE_SHORTHAND' => 'w',  'FILTER_WAREHOUSE' => 'warehouseid', 'FILTER_LOCATIONKEY' => 'locationrefkey', 'FILTER_WAREHOUSEGROUP' => 'record#',
                                              'FIELDS' => array(
                                                    'w.record#                         as WAREHOUSEDIMKEY',
                                                    'w.warehouseid                     as WAREHOUSE',
                                                    'w.name                            as WAREHOUSENAME',
                                                    'w.shiptokey                       as SHIPTOKEY',
                                                    'w.locationrefkey                  as LOCATIONKEY',
                                                )
                                            ),
            'ICITEM'                => array( 'FILE_SHORTHAND' => 'i',  'FILTER_ITEM' => 'itemid', 'FILTER_ITEMGROUP' => 'record#', 'FILTER_PRODUCTLINEID' => 'productlinekey',
                                              'FIELDS' => array(
                                                    'i.record#                         as ITEMDIMKEY',
                                                    'i.itemid                          as ITEM',
                                                    'i.name                            as ITEMNAME',
                                                    'i.productlinekey                  as PRODUCTLINEID',
                                                    'i.itemtype                        as ITEMTYPE',
                                                    'i.uomgrpkey                       as UOMGROUPKEY',
                                                    'i.default_unit_of_measure         as ITEM_UNITS_OF_MEASURE',
                                                    'i.reorder_point                   as I_REORDER_POINT',
                                                    'i.safety_stock                    as I_SAFETY_STOCK',
                                                    'i.sales_forecast_method           as I_METHOD',
                                                    'i.reorder_qty                     as I_REORDER_QTY',
                                                    'i.max_order_qty                   as I_MAX_ORDER_QTY',
                                                )
                                            ),
            // identical to ICITEM but fewer fetched fields....
             'ICITEM2'              => array( 'FILE_SHORTHAND' => 'i', 'FILE' => 'ICITEM', 'FILTER_ITEM' => 'itemid', 'FILTER_ITEMGROUP' => 'record#', 'FILTER_PRODUCTLINEID' => 'productlinekey',
                                              'FIELDS' => array(
                                                  'i.itemid                           as ITEM',
                                                  'i.itemtype                         as ITEMTYPE', // could be a kit
                                              )
                                        ),
            // identical to ICITEM but only gets kits....
             'ICITEM_KITS'              => array( 'FILE_SHORTHAND' => 'i', 'FILE' => 'ICITEM', 'FILTER_ITEM' => 'itemid', 'FILTER_ITEMGROUP' => 'record#', 'FILTER_PRODUCTLINEID' => 'productlinekey',
                                              'FIELDS' => array(
                                                  'i.itemid                          as ITEM',
                                                  'i.itemtype                        as ITEMTYPE',
                                                  'i.uomgrpkey                       as UOMGROUPKEY',
                                                  'i.default_unit_of_measure         as ITEM_UNITS_OF_MEASURE',
                                                  'i.reorder_point                   as I_REORDER_POINT',
                                                  'i.safety_stock                    as I_SAFETY_STOCK',
                                                  'i.sales_forecast_method           as I_METHOD',
                                                  'i.reorder_qty                     as I_REORDER_QTY',
                                                  'nvl(i.max_order_qty, 0)           as I_MAX_ORDER_QTY',
                                              )
                                        ),
            'ICITEMWHSE'            => array( 'FILE_SHORTHAND' => 'iw', 'FILTER_ITEM' => 'itemkey', 'FILTER_WAREHOUSE' => 'warehousekey', 'FIELDS' => array(
                                                    'iw.reorder_point                  as REORDER_POINT',
                                                    'iw.safety_stock                   as SAFETY_STOCK',
                                                    'iw.sales_forecast_method          as METHOD',
                                                    'iw.reorder_qty                    as REORDER_QTY',
                                                    'nvl(iw.max_order_qty, 0)          as W_MAX_ORDER_QTY',
                                                    'iw.record#                        as ITEMWHSEKEY',      // other records refer to this record number as the itemwhsekey
                                                ),
                                        ),
            'ICITEMVENDOR'         => array( 'FILE_SHORTHAND' => 'iv', 'FIELDS' => array(
                                                    'iv.record#                        as IV_ROWNUM',
                                                    'iv.stock_number',
                                                    'iv.lead_time',
                                                    'iv.economic_order_qty',
                                                    'iv.min_order_qty', // note: there IS a max_order_qty, but it is not shown on the UI
                                                    'iv.uom',
                                                    'iv.convfactor',
                                                    'iv.forecast_demand_in_lead_time',
                                                    'iv.preferred_vendor',
                                                ),
                                        ),
            'ICITEMWHSEVEND'       => array( 'FILE_SHORTHAND' => 'iwv', 'FILE' => 'ICITEMVENDOR', 'FIELDS' => array(    // item warehouse vendor shares sql tables with icitemvendor
                                                    'iwv.record#                      as IV_ROWNUM',
                                                    'iwv.stock_number',
                                                    'iwv.lead_time',
                                                    'iwv.economic_order_qty',
                                                    'iwv.min_order_qty', // note: there IS a max_order_qty, but it is not shown on the UI
                                                    'iwv.uom',
                                                    'iwv.convfactor',
                                                    'iwv.forecast_demand_in_lead_time',
                                                    'iwv.preferred_vendor',
                                                ),
                                        ),
             'ICITEMACTIVITY'        => array( 'FILE_SHORTHAND' => 'ia', 'FILTER_ASOFDATE' => 'whencreated', 'FIELDS' => array(
                                                     "SUM(NVL(DECODE(ict.name,'ONORDER',NVL(ia.quantity,0)),0)) AS onorder",
                                                     // "SUM(NVL(DECODE(ict.name,'ONHAND', NVL(ia.quantity,0)),0)) AS onhand",  // no longer accurate!
                                                     "SUM(NVL(DECODE(ict.name,'ONHOLD', NVL(ia.quantity,0)),0)) AS onhold",
                                                 )
                                        ),
             'ICITEMACTIVITY2'       => array( 'FILE_SHORTHAND' => 'ia', 'FILE' => 'ICITEMACTIVITY', 'FILTER_ASOFDATE' => 'whencreated', 'FIELDS' => array(
                                                     "{PLACEHOLDER}", // filled in by client
                                                 )
                                       ),
             'ICITEMACTIVITY3'       => array( 'FILE_SHORTHAND' => 'ia', 'FILE' => 'ICITEMACTIVITY', 'FIELDS' => array(
                                                     "MAX(ia.whencreated) as MostRecent",
                                                 )
                                     ),
             'ICTOTAL'              => array( 'FILE_SHORTHAND' => 'ict'),
             'DOCHDR_IA'            => array( 'FILE_SHORTHAND' => 'hdr', 'FILE' => 'DOCHDR', 'FIELDS' => array(
                                                     'hdr.record#                AS hdr_record#',
                                                     'hdr.vendentity             AS hdr_vendorname'
                                                 )
                                        ),
             'DOCPAR'               => array( 'FILE_SHORTHAND' => 'par', 'FIELDS' => array(
                                                     'par.sale_pur_trans         AS spi'
                                                 )
                                        ),
             'ICITEMCOMPONENT'      => array( 'FILE_SHORTHAND' => 'kitpart', 'FILTER_ITEM' => 'itemkey', 'FIELDS' => array( // note: shenanigans afoot for the FILTER_ITEM; see code....
                                                     'kitpart.itemkey            AS ITEMID',
                                                     'kitpart.componentkey       AS PART',
                                                     'kitpart.unit               AS UNIT',
                                                     'kitpart.quantity           AS QUANTITY',
                                                 )
                                         ),
            'ITMHISTCOST'           => array( 'FILE_SHORTHAND' => 'ihc', 'FILTER_ITEM' => 'itemkey', 'FILTER_WAREHOUSE' => 'whsekey', 'FILTER_ASOFDATE' => 'ason', 'FIELDS' => array(
                                                    'ihc.itemkey            AS ITEM',
                                                    'ihc.whsekey            AS WAREHOUSE',
                                                    'ihc.ason',
                                                    'ihc.qtyonhand          AS ONHAND',
                                                    'ihc.lastcost',
                                                    'MAX(ason) OVER (PARTITION BY ihc.cny#, ihc.itemkey, ihc.whsekey) AS max_ason'
                                                )
                                        ),
        );


            // the basic WHERE clauses for each table; file shorthand is known here (from the table above)
         $this->joins = array(
             'ICITEM'               => array( 'i.cny# = :1',  "i.itemtype IN ('I','SK')", "i.ENABLE_REPLENISHMENT = 'T'", "i.status = 'T'"),
             'ICITEM2'              => array( 'i.cny# = :1',  "i.itemtype IN ('I','SK')", "i.ENABLE_REPLENISHMENT = 'T'", "i.status = 'T'"),
             'ICITEM_KITS'          => array( 'i.cny# = :1',  "i.itemtype = 'SK'",        "i.ENABLE_REPLENISHMENT = 'T'", "i.status = 'T'"),    // ONLY KITS
             'ICWAREHOUSE'          => array( 'w.cny# = :1',  "w.ENABLE_REPLENISHMENT = 'T'", "w.status = 'T'"),
             'ICITEMWHSE'           => array( 'iw.cny# = :1', "iw.itemkey = i.itemid", "iw.warehousekey = w.warehouseid", "iw.ENABLE_REPLENISHMENT = 'T'" ), // MUST be paired with item and warehouse!
             'VENDOR'               => array( 'v.cny# = :1',  "v.status = 'T'" ),                       // must be paired with either itemvendor or itemwarehousevendor
             'ICITEMVENDOR'         => array( 'iv.cny# = :1', "iv.itemkey = i.itemid", "v.vendorid = iv.vendorid", "i.itemtype = 'I'" ),  // MUST BE PAIRED WITH ITEM and VENDOR, exclude kits
             'VENDTYPE'             => array( 'vt.cny# = :1', "v.vendtypekey = vt.record#" ), // MUST be paired with VENDOR
             'TERM'                 => array( 't.cny# = :1', /* "(v.termskey is null or v.termskey = t.record#)" */ ), // note: most termskeys are null, so this isn't working as a join.
             'ICITEMWHSEVEND'       => array( 'iwv.cny# = :1', 'iwv.ITEMWHSEKEY = iw.record#', 'iwv.vendorid = v.vendorid', "i.itemtype = 'I'"),  // MUST BE PAIRED WITH ITEM and VENDOR
             'ICITEMACTIVITY'       => array( 'ia.cny# = :1', 'ia.itemkey =  i.itemid', 'w.warehouseid   = ia.warehousekey'),   // needs item/wareshouse and ictotal
             'ICITEMACTIVITY2'      => array( 'ia.cny# = :1', 'ia.itemkey =  i.itemid', 'w.warehouseid   = ia.warehousekey'),   // needs item/wareshouse and ictotal
             'ICITEMACTIVITY3'      => array( 'ia.cny# = :1', 'ia.itemkey =  i.itemid', "par.sale_pur_trans = 'P'", "hdr.vendentity is not null" ),
             'ICTOTAL'              => array( 'ict.cny# = :1', 'ia.totalkey = ict.record#' ),
             'DOCHDR_IA'            => array( 'hdr.cny# = :1', 'hdr.record# = ia.PARENTDOCHDRKEY' ),    // specifically to tie to the item activity table
             'DOCPAR'               => array( 'par.cny# = :1', 'par.record# = hdr.DOCPARKEY' ),
             'ICITEMCOMPONENT'      => array( 'kitpart.cny# = :1'),
             'ITMHISTCOST'          => array( 'ihc.cny# = :1', /* 'ason = max_ason' */ ),
         );
        if ( IsMultiEntityCompany() && IsRoot() ) {
            $this->joins['ICWAREHOUSE'][] = 'w.locationrefkey IS NOT NULL';  // need default ref location when root
        }

         // We query against these sql table groups.  'true' means include it unconditionally.  Otherwise a filter name or array of filter names.
         //  So, for example, if you include vendor, include vendortype if the FILTER_VENDOR_TYPE is present
         $this->tableGroups = array(
            "ITEM_VENDOR"               => array( "ICITEM" => true, "ICITEMVENDOR" => true, "VENDOR" => true, 'VENDTYPE' => 'FILTER_VENDOR_TYPE', /* 'TERM' => true */),
            "ITEM_WAREHOUSE"            => array( "ICITEM" => true, "ICWAREHOUSE" => true,  "ICITEMWHSE" => true, ),
            "ITEM_WAREHOUSE_VENDOR"     => array( "ICITEM" => true, "ICWAREHOUSE" => true,  "ICITEMWHSE" => true, "VENDOR" => true, 'VENDTYPE' => 'FILTER_VENDOR_TYPE', 'ICITEMWHSEVEND' => true , /* 'TERM' => true */ ),
            "WAREHOUSES"                => array( "ICWAREHOUSE" => true ),
            "PAST_ACTIVITY"             => array( "ICITEM2" => true, "ICWAREHOUSE" => true,  'ICITEMACTIVITY' => true,'ICTOTAL' => true ),
            "FUTURE_ACTIVITY"           => array( "ICITEM2" => true, "ICWAREHOUSE" => true,  'ICITEMACTIVITY2' => true,'ICTOTAL' => true, 'DOCHDR_IA' => true, 'DOCPAR' => true ),
            "LAST_PURCHASE_FROM"        => array( "ICITEM2" => true, 'ICITEMACTIVITY3' => true, 'DOCHDR_IA' => true, 'DOCPAR' => true ),    // no total rec, no warehouse
            "KIT_PARTS"                 => array( "ICITEMCOMPONENT" => true ),
            "GET_KITS"                  => array( "ICITEM_KITS" => true ),
            "GET_ONHAND"                => array( "ITMHISTCOST" => true ),
            "TERM"                      => array( "TERM" => true ),
         );

        // For those queries dealing in time (after 'now', on-or-before-now), which time period does the query want?
        // Specifically, this is the relationship between the user-specified 'as of date'.
        $this->tableTimePeriod = array(
            "PAST_ACTIVITY"             => self::ON_OR_BEFORE_NOW,
            "FUTURE_ACTIVITY"           => self::AFTER_NOW,
            "LAST_PURCHASE_FROM"        => self::ON_OR_BEFORE_NOW,
            "GET_ONHAND"                => self::ON_OR_BEFORE_NOW,
        );

        // if there should be a group by, put it here.  This is clunky because you have to know all the fields being fetched that are in the group by :-(
         $this->groupBy = array(
             'PAST_ACTIVITY'           =>  "i.itemid,i.itemtype,w.record#,w.warehouseid,w.name,w.shiptokey,w.locationrefkey",
             'LAST_PURCHASE_FROM'      =>  "i.itemid,i.itemtype,hdr.record#,hdr.vendentity,par.sale_pur_trans",
         );

        // if there should be a order by, put it here.
        $this->orderBy = array(
            'ITEM_VENDOR'           => "upper(i.itemid),upper(v.vendorid)",     // use 'upper()' for a case-insensitive sort
            'ITEM_WAREHOUSE'        => "upper(i.itemid),upper(w.warehouseid)",
            'ITEM_WAREHOUSE_VENDOR' => "upper(i.itemid),upper(w.warehouseid),upper(v.vendorid)",
            'LAST_PURCHASE_FROM'    => "upper(i.itemid), MostRecent desc, hdr.record# desc",
            'WAREHOUSES'            => "upper(w.warehouseid)",
        );

        $gManagerFactory            = Globals::$g->gManagerFactory;
        $this->replenishDetailMgr   = $gManagerFactory->getManager('replenishdetail', $params);
        $this->pricingHandler       = $gManagerFactory->_getObjectInstance('PricingHandler');
        $this->contactMgr           = $gManagerFactory->getManager("contact");
        $this->exchMgr              = $gManagerFactory->getManager('exchangerate');

        $this->myLocationName       =  $this->getLocationNameFromRecordNumber(GetContextLocation(false));   // gets the full name, not just location_no

        $this->pricingHandler->CacheQueries(true);  // we use this a lot, so engage the cache
    }


    // Note: as of May, 2018, PHP inspections complains that the method is not referenced.  It IS, but as a string to usort().
    /** @noinspection PhpUnusedPrivateMethodInspection */
    /**
     *  final Sort Preferred Vendor - this is the COMPARE FUNCTION for usort() for the final returned-array of line items to the UI.
     *
     * @param array $l
     * @param array $r
     *
     * @return int
     *
     */
    private static function  finalSortPreferredVendor($l, $r)
    {
        $rtn = 0;
        if ($l['WAREHOUSE_ITEM_GROUP'] < $r['WAREHOUSE_ITEM_GROUP']) {
            $rtn = -1;
        } else if ($l['WAREHOUSE_ITEM_GROUP'] > $r['WAREHOUSE_ITEM_GROUP']) {
            $rtn = +1;
        } else {
            if ($l['PREFERRED_VENDOR'] == 'T') {
                $rtn = -1;
            } else if ($r['PREFERRED_VENDOR'] == 'T') {
                $rtn = +1;
            } else {
                if ($l['IV_ROWNUM'] < $r['IV_ROWNUM']) {
                    $rtn = -1;
                } else if ($l['IV_ROWNUM'] > $r['IV_ROWNUM']) {
                    $rtn = +1;
                }
            }
        }
        return $rtn;
    }


    // Note: as of May, 2018, PHP inspections complains that the method is not referenced.  It IS, but as a string to usort().
    /** @noinspection PhpUnusedPrivateMethodInspection */
    /**
     *  final Sort Shortest Vendor - this is the COMPARE FUNCTION for usort() for the final returned-array of line items to the UI.
     *
     * @param array $l
     * @param array $r
     *
     * @return int
     *
     */
    private static function finalSortShortestVendor($l, $r)
    {
        $rtn = 0;
        if ($l['WAREHOUSE_ITEM_GROUP'] < $r['WAREHOUSE_ITEM_GROUP']) {
            $rtn = -1;
        } else if ($l['WAREHOUSE_ITEM_GROUP'] > $r['WAREHOUSE_ITEM_GROUP']) {
            $rtn = +1;
        } else {
            $leadTimeLeft  = $l['LEAD_TIME'];
            $leadTimeRight = $r['LEAD_TIME'];
            if ($leadTimeLeft < $leadTimeRight) {
                $rtn = -1;
            } else if ($leadTimeLeft > $leadTimeRight) {
                $rtn = +1;
            } else {
                // stabalize via item/vendor order on the lists
                if ($l['IV_ROWNUM'] < $r['IV_ROWNUM']) {
                    $rtn = -1;
                } else if ($l['IV_ROWNUM'] > $r['IV_ROWNUM']) {
                    $rtn = +1;
                }
                // IV_ROWNUMs should be unique, and so they shouldn't be ==, but....
            }
        }
        return $rtn;

    }


    // Note: as of May, 2018, PHP inspections complains that the method is not referenced.  It IS, but as a string to usort().
    /** @noinspection PhpUnusedPrivateMethodInspection */
    /**
     *  final Sort Most Recent Vendor - this is the COMPARE FUNCTION for usort() for the final returned-array of line items to the UI.
     *
     * @param array $l
     * @param array $r
     *
     * @return int
     *
     */
    private static function finalSortMostRecentVendor($l, $r)
    {
        $rtn = 0;
        if ($l['WAREHOUSE_ITEM_GROUP'] < $r['WAREHOUSE_ITEM_GROUP']) {
            $rtn = -1;
        } else if ($l['WAREHOUSE_ITEM_GROUP'] > $r['WAREHOUSE_ITEM_GROUP']) {
            $rtn = +1;
        } else {
            $mostRecentLeft  = $l['MOST_RECENT'];
            $mostRecentRight = $r['MOST_RECENT'];
            if ($mostRecentLeft < $mostRecentRight) {
                $rtn = -1;
            } else if ($mostRecentLeft > $mostRecentRight) {
                $rtn = +1;
            } else {
                // stabalize via item/vendor order on the lists
                if ($l['IV_ROWNUM'] < $r['IV_ROWNUM']) {
                    $rtn = -1;
                } else if ($l['IV_ROWNUM'] > $r['IV_ROWNUM']) {
                    $rtn = +1;
                }
                // IV_ROWNUMs should be unique, and so they shouldn't be ==, but....
            }
        }
        return $rtn;

    }


    // Note: as of May, 2018, PHP inspections complains that the method is not referenced.  It IS, but as a string to usort().
    /** @noinspection PhpUnusedPrivateMethodInspection */
    /**
     *  final Sort Low Cost Vendor - this is the COMPARE FUNCTION for usort() for the final returned-array of line items to the UI.
     *
     * @param array $l
     * @param array $r
     *
     * @return int
     *
     */
    private static function finalSortLowCostVendor($l, $r)
    {
        $rtn = 0;
        if ($l['WAREHOUSE_ITEM_GROUP'] < $r['WAREHOUSE_ITEM_GROUP']) {
            $rtn = -1;
        } else if ($l['WAREHOUSE_ITEM_GROUP'] > $r['WAREHOUSE_ITEM_GROUP']) {
            $rtn = +1;
        } else {
            // note: since we are comparing different vendors, there could be different exchange rates
            $costLeft  = $l['PURCHASE_PRICE'] * $l['EXCHANGE_RATE'];
            $costRight = $r['PURCHASE_PRICE'] * $r['EXCHANGE_RATE'];
            if ($costLeft < $costRight) {
                $rtn = -1;
            } else if ($costLeft > $costRight) {
                $rtn = +1;
            } else {
                // stabalize via item/vendor order on the lists
                if ($l['IV_ROWNUM'] < $r['IV_ROWNUM']) {
                    $rtn = -1;
                } else if ($l['IV_ROWNUM'] > $r['IV_ROWNUM']) {
                    $rtn = +1;
                }
                // IV_ROWNUMs should be unique, and so they shouldn't be ==, but....
            }
        }
        return $rtn;
    }


    /**
     * Get the doctype for this document.
     *  Note: well, this normally comes from a DocumentManager, which I don't inherit from,
     *      but I *do* have a doc type!
     *
     * @return  string
     */
    function getDocType()
    {
        return $this->_docType;
    }


    /**
     * Set the doctype here and in the entry manager.
     *
     * @param string $docType
     */
    function setDocType($docType)
    {
        $this->_docType = $docType;
        $this->replenishDetailMgr->setDocType($docType);
    }


    /**
     *      push Filters - push the filters onto a stack so we can restore them just as we found them....
     *              This can be nested in true stack fassion, just POP the filters wherever you PUSHED them
     *
     * @param string[] $values
     *
     */
    private function pushFilters($values)
    {
        // save the filters since we change them:
        $oldFilters = array();
        foreach ($this->filters as $saveFilter) {
            if (isset($values[$saveFilter])) {
                $oldFilters[$saveFilter] = $values[$saveFilter];
            }
        }
        $this->parametersStack[] = $oldFilters;
    }


    /**
     *      pop Filters - restore the filters into the paramter list from the stack.
     *              of course, you must have SAVED the filters before this call
     *
     * @param string[] $values
     *
     */
    private function popFilters(&$values)
    {
        $oldFilters = array_pop($this->parametersStack);

        foreach ($this->filters as $saveFilter) {
            if (isset($oldFilters[$saveFilter])) {
                $values[$saveFilter] = $oldFilters[$saveFilter];
            }
        }

    }


    /**
     *  getCurrencyForLocation - given an intaernal location ID (record number, get the currency for that location
     *
     * @param string $loc
     *
     * @return string
     */
    private function getCurrencyForLocation($loc)
    {
        static $cache = array();
        if ( ! isset($cache[$loc])) {
            $cache[$loc] = GetLocationBaseCurrency($loc, false);      // false is 'use record number, not name'
        }
        return $cache[$loc];
    }



    //  ****************************************************************************************
    //  ****************************************************************************************
    //
    //      Generate A Snapshot
    //
    //      The general work flow for the UI is this:
    //          - Generate a snapshot ( generateSnapshot() or use API_Add() )
    //          - Persist the snapshot header
    //          - If they request a 'named snapshot', then persist the snapshot with that name (deleting any old snapshot with the same name)
    //          - return the snapshot records
    //
    //          - UI edits the snapshot and then calls UpdateSnapshot() or API_Set()
    //          - if a named snapshot, then we persist the changes (deleting the old snapshot if one)
    //
    //          - if they request POs, we generate them and update the header
    //          - for now, there is a compressed blob with CSV output on what POs were generated and their status (any errors, etc)
    //
    //          - The UI can come back later and get the snapshot by name if they want, using the API or getSnapshot()
    //          - (API meaning they get the header from here and the detail records from ReadByQuery on the replenishdetail manager)
    //
    //  ****************************************************************************************
    //  ****************************************************************************************

    /**
     *      Generate a snapshot from the passed filter parameters
     *
     * @param string[]  $values  includes filters and other information; see the spec
     * @param array     $snapshotData returned, the entire snapshot
     *
     * @return bool
     */
    function generateSnapshot(&$values, &$snapshotData)
    {
        // save the filters since we change them:
        $this->pushFilters($values);
        foreach ($this->filters as $saveFilter) {
            if (isset($values[$saveFilter]) && is_string($values[$saveFilter]) && (strpos($values[$saveFilter], '--') !== false)) {
                list($values[$saveFilter]) = explode('--', $values[$saveFilter]);   // remove the -- between the id and the name, if one
            }
        }

        $snapshotData = array();
        $this->setDocType($values['TRANSACTION_DEFINITION']);   // this is needed to populate custom dimensions and other such things

        $this->getUOMGroups();
        $ok = true;

        // Make sure replenishment is on and this customer is valid to use it
        // Make sure needed fields are present in $values
        $ok = $ok && $this->validateAndCleanupValues( self::GENERATE_SNAPSHOT, $values );

        // Fill in the snapshot table of data (rows of item/warehouse/vendor data)
        $ok = $ok && $this->getDataForSnapshot($values, $snapshotData);

        // Sometimes, dimensions are restricted where, for example, an item can only have one customer.
        if ($ok) {
            $this->handleDimensionRelationships($snapshotData);
        }

        // put the filter values back
        $this->popFilters($values);

        return $ok;
    }


    /**
     * @param array $snapshotData
     */
    private function handleDimensionRelationships(&$snapshotData)
    {
        // Document forms get data via an ajax call and otherwise use a bunch-o-default logic that I don't have.
        // So this is our distilation of the relationship goodness, and likely very flawed..
        $relatedCache = [];

        // todo: the cache is broken over in the data field def manager, and this GREATLY slows us down.
        // Pt_DataFieldDefManager::$useFieldCache        = true;          // speed up where we can by turning on optional caches
        Pt_RelationshipController::resetRelatedDataState();
        $translateReplenishmentToSystem = [             // iterate through these, applying the key as the value for processing
            'ITEM'          => 'ITEMID',
            'WAREHOUSE'     => 'WAREHOUSEID',
            'VENDORID'      => 'VENDORID',
            'LOCATION_NAME' => 'LOCATION', // 'LOCATION_NO',

        ];

        foreach ($snapshotData as &$row) {
            foreach ($translateReplenishmentToSystem as $key => $value) {
                $inputFieldName = $value;
                $row[$inputFieldName] = $row[$key];
                $inputDataObjId = $row[$inputFieldName];
                if (!isset($relatedCache[$inputFieldName][$inputDataObjId])) {
                    $related = Pt_RelationshipController::getRelated($inputFieldName, $inputDataObjId);   // this costs sql time
                    $relatedCache[$inputFieldName][$inputDataObjId] = $related['related_fields'] ?? [];
                }
                foreach ($relatedCache[$inputFieldName][$inputDataObjId] as $related) {
                    if (isset($related['field'], $related['value'])) {
                        $row[$related['field']] = $related['value'];
                    }
                }
            }
        }
    }

    /**
     *  get UOM Groups - get the entire list of unit-of-measure groups.
     *  Relax!  There are only a handful of these....
     */
    private function getUOMGroups()
    {
        // I want to know the UOM Groups for display, get ALL of those (there are only a handfull)...
        $stmt = array();
        $stmt[0] = "SELECT grp.record#, grp.name, uom.unit, uom.convfactor
                        FROM icuomgrp grp, icuom uom 
                        WHERE grp.cny#=:1 and uom.cny#=:1 AND grp.podefunitkey=uom.record# ";
        $stmt[1] = GetMyCompany();
        $res     = QueryResult($stmt);
        if ($res !== false) {
            foreach ($res as $uomgroup) {
                $this->UOMGroups[$uomgroup['RECORD#']] = array('NAME' => $uomgroup['NAME'], 'DEFAULT_UNIT' => $uomgroup['UNIT'], 'CONVFACTOR' => $uomgroup['CONVFACTOR'],);
            }
        }
    }



    /**
     *  get conversion factor for UOM
     *
     * @param string $uom
     * @param string $uomGroupKey
     *
     * @return float
     */
    private function getConvFactorFromUOM($uom, $uomGroupKey)
    {
        // Cache these because, in practice, we only use a few.
        if ( ! isset($this->uomCache[$uom][$uomGroupKey])) {
            $qry = "SELECT uom.convfactor FROM   icuom uom  WHERE  uom.cny#=:1 AND uom.unit=:2 AND uom.grpkey=:3 ";
            $stmt = [ $qry, GetMyCompany(),$uom, $uomGroupKey ];

            $res = QueryResult($stmt);
            if ($res !== false) {
                $convfactor = (float)($res[0]['CONVFACTOR']);
                if ($convfactor == 0.0) {
                    $convfactor = 1.0;    // odd, but happens (0 isn't a valid value)
                }
            } else {
                $convfactor = 1.0;  // well, default to SOMETHING valid.
            }
            $this->uomCache[$uom][$uomGroupKey] = $convfactor;
        }
        return $this->uomCache[$uom][$uomGroupKey];
    }


    /**
     *      get Item List get the list of items from the filters, OR kit parts
     *
     * @param string[]  $parameters        filtes and such
     * @param array     $itemList          fetched data for items
     * @param array     $warehouseList     list of possible wareoiuses
     * @param string[]  $terms             list of term names by record number
     *
     * @return bool
     */
    private function getItemList($parameters, &$itemList, &$warehouseList, &$terms)
    {
        // 1) Add the item/warehouse/vendor list
        //  These can override the item/vendor list entries
        if (! $this->getItemWarehouseVendorList( $parameters, $itemList, $terms )) {
            return false;
        }

        // 2) Add the item/vendor list to item/warehouse pairs.
        //  note that there can be more warehouses than were explicitly
        //  defined as item/warehouse records.
        //  DO NOT ADD THESE TO WAREHOUSES FROM ABOVE
        //  (i.e. we get EITHER the item/warehouse/vendor list OR the item/vendor list for one warehouse)
        if (!$this->getItemVendorList($parameters, $itemList, $warehouseList, $terms)) {
            return false;
        }

        // 2.5) Are we searching just for Stockable Kits, and they have no vendor info?
        if (!$this->getStockableKits($parameters)) {
            return false;
        }

        // 3) Get On-Hand, On-Order, On-Hold
        $this->getHistoricalTransactions( $parameters, $itemList );

        // 4) Get the future transactions
        $this->updateListWithFututreTransactions( $parameters, $itemList );

        // 5) if we need to sort by last-vendor-purchased-from, get THAT data as well.
        if (isset($parameters['SHOW_VENDOR_OPTION_INTERNAL']) && ($parameters['SHOW_VENDOR_OPTION_INTERNAL'] == 'LAST_VENDOR')) {
            $this->getMostRecentVendorPurchaseForItem( $parameters, $itemList );
        }
        return true;
    }


    /**
     *      out Of Time - the reading process has taken too long and we're in danger of timing out the browser.  Let the customer know.
     *
     * @return bool
     */
    private function outOfTime()
    {
        Globals::$g->gErr->addIAError('INV-0239', __FILE__ . ':' . __LINE__,
        "The replenishment information can't be populated because there are too many items,
        warehouses and vendors to retrieve. Use the filters to narrow the search and try again.",[]);

        return false;
    }


    /**
     * @param string[]  $parameters       passed in from the XML API or UI
     * @param array     $snapshotData     returned data
     *
     * @return bool
     */
    private function getDataForSnapshot($parameters, &$snapshotData)
    {
        $itemList           = array();
        $startTime          = time();
        $terms              = array();
        $errorCheckpoint    = Globals::$g->gErr->Checkpoint();
        $snapshotData       = [];


        // are we ONLY diagnosing problems and not producing a snapshot?
        $diagnose = (($parameters['DIAGNOSE'] ?? false) === true);
        if ($diagnose) {
            if (($parameters['FILTER_ITEM'] ?? null) === null) {
                Globals::$g->gErr->addIAError('INV-0240', __FILE__ . ':' . __LINE__,
                    "The filters must at least have an item (and not an item group) specified for the diagnostics to work.",
                    [],
                    "Enter an item and try again",[]);
                return false;
            }
        }


        // many vendor records have no term; get all terms here, indexed by the record number
        $termValues = QueryResult($this->buildSqlQuery($parameters, 'TERM'));
        if ($termValues !== false) {
            foreach ($termValues as $oneTerm) {
                $terms[$oneTerm['TERM_RECORDNO']] = $oneTerm['TERMSNAME'];
            }
        }

        $this->getForecastTableEntries($parameters['FILTER_ASOFDATE']);

        // How are we doing on time?
        $timeNow = time();
        if (($timeNow - $startTime) > self::TIME_LIMIT_SECONDS) {
            return $this->outOfTime();
        }

        // 1) Get the list of possible warehouses
        $warehouseList = $this->getWarehouseList( $parameters );
        if ((count($warehouseList) == 0) || (Globals::$g->gErr->Checkpoint() != $errorCheckpoint)) {
            return false;   // if we get no warehouses, we have an error condition
        }

        // 2) Get the base item list
        if ((! $this->getItemList( $parameters, $itemList, $warehouseList, $terms )) || (Globals::$g->gErr->Checkpoint() != $errorCheckpoint)) {
            return false;
        }

        // How are we doing on time?
        $timeNow = time();
        if (($timeNow - $startTime) > self::TIME_LIMIT_SECONDS) {
            return $this->outOfTime();
        }

        // 3) Get Kit Parts - this may call getItemList() again....
        if ((! $this->getKitParts( $parameters, $itemList, $warehouseList, $terms )) || (Globals::$g->gErr->Checkpoint() != $errorCheckpoint)) {
            return false;
        }

        // How are we doing on time?
        $timeNow = time();
        if (($timeNow - $startTime) > self::TIME_LIMIT_SECONDS) {
            return $this->outOfTime();
        }

        // mostly done: turn the arrays into a flat list
        $snapshotData = $this->flattenArrayAndFinishRecords( $parameters, $itemList );

        // FINALLY, compute the price now that we know the quantities and everything else.
        //      Note: this can be very very slow.
        $this->getPricing( $parameters, $snapshotData );

        // Now sort the vendors into order so the UI can show them how the customer wants them....
        switch ($parameters['SHOW_VENDOR_OPTION_INTERNAL']) {   // The internal version, not language dependant
            case 'PREF_VENDOR': // preferred vendor
                usort($snapshotData, 'ReplenishmentManager::finalSortPreferredVendor');
                break;
            case 'LAST_VENDOR': // most recently purchased from
                usort($snapshotData, 'ReplenishmentManager::finalSortMostRecentVendor');
                break;
            case 'LOW_VENDOR':  // lowest price
                usort($snapshotData, 'ReplenishmentManager::finalSortLowCostVendor');
                break;
            default:
                // SHORTEST_VENDOR (shortest lead time)
                usort($snapshotData, 'ReplenishmentManager::finalSortShortestVendor');
                break;
        }
        return (Globals::$g->gErr->Checkpoint() == $errorCheckpoint);   // anyone post any errors?
    }


    /**
     * @param string $method
     *
     * @return string
     */
    private function getMethodFromPrefsIfNeedBe($method)
    {
        if ($method == '') {
            $method = ReplenishDetailManager::getInternalSalesForecastMethod($this->inventoryPrefs['FORECAST_METHOD'] ?? '');
        }
        return $method;
    }


    /**
     *
     *  get Kit Parts - if we have a kit in our item list, we need to make sure we have all the PARTS to that kit as well.
     *                  and we want to get enough parts to satisfy the kit.  Here, we get the parts into the itemList and
     *                  we save info for later when we're figuring out how many of each item we need.
     *                  We need what the part needs PLUS what it's kit needs.
     *
     *                  Remember that multiple kits can have the same parts ('paper', for example),
     *                  and that a kit part may itself be a kit (a sub-assembly).  AND that not all parts
     *                  are items/kits (like 'Installation', a service), AND that not all parts are enabled
     *                  for replenishment.
     *
     *                  Finally, note that this routine calls itself recursively, so don't do anything to break that.
     *
     * @param string[]  $parameters        passed in from the XML API or UI
     * @param array     $itemList          the items we have gathered, kits or not
     * @param array     $warehouseList     list of warehouses
     * @param string[]  $terms             list of term names by record number
     *
     * @return bool
     */
    private function getKitParts($parameters, &$itemList, &$warehouseList, $terms)
    {
        $this->pushFilters($parameters);
        $kitPartsToGet  = [];
        // $itemToPart     = [];
        $ok             = true;

        do {
            // 1) ARE there kits here?
            //      Note that we look for items with vendors for the itemList, and KITS DON'T ALWAYS HAVE VENDORS.
            //      So here we do a query to get the kits that match the filters, if any.
            $rtn = QueryResult($this->buildSqlQuery($parameters, 'GET_KITS'));
            if ($rtn === false) {
                break;    // there is no error, but there were no kits  (well, if there IS an error we'll catch it later)
            }

            $itemIsStockableKitLocalizedStr = null;
            $itemContainsPartLocalizedStr = null;
            foreach ($rtn as $kit) {
                // Normally these would come from a vendor, but we don't have a vendor, so use the item values
                $itemID          = $kit['ITEM'];
                $kitPartsToGet[] = $itemID;             // we need the list of parts for this kit
                if (!isset($kit['ITEM_UNITS_OF_MEASURE'])) {
                    $kit['ITEM_UNITS_OF_MEASURE'] = $this->UOMGroups[$kit['UOMGROUPKEY']]['DEFAULT_UNIT'];
                }
                $kit['ITEM_CONVFACTOR'] = $this->getConvFactorFromUOM($kit['ITEM_UNITS_OF_MEASURE'], $kit['UOMGROUPKEY']);
                if (isset($this->kitInfo[$itemID])) {
                    $kit = array_merge($this->kitInfo[$itemID], $kit);
                }
                $this->kitInfo[$itemID]         = $kit;         // save for later
                $this->longestLeadTime[$itemID] = 0;            // we don't NEED this, but it helps us know if we've seen this item before.

                if (($parameters['DIAGNOSE'] ?? false) === true) {
                    if (!$itemIsStockableKitLocalizedStr) {
                        $tokens = [
                            [
                                'id' => 'IA.ITEM_IS_STOCKABLE_KIT',
                                'placeHolders' => [
                                    ['name' => 'ITEM_ID', 'value' => "\'%s\'"]
                                ]
                            ],
                            [
                                'id' => 'IA.ITEM_CONTAINS_PART',
                                'placeHolders' => [
                                    ['name' => 'ITEM_ID', 'value' => "\'%1s\'"],
                                    ['name' => 'ITEM_ID_PART', 'value' => "\'%2s\'"]
                                ]
                            ]
                        ];
                        $text = getLocalizedTextWithThrow($tokens);
                        $itemIsStockableKitLocalizedStr = GT($text, 'IA.ITEM_IS_STOCKABLE_KIT');
                        $itemContainsPartLocalizedStr = GT($text, 'IA.ITEM_CONTAINS_PART');
                    }
                    $this->diagnostics .= sprintf($itemIsStockableKitLocalizedStr, $itemID);
                }
            }

            // 1b) no kits?  Easy peazy
            if (count($kitPartsToGet) > 0) {
                // 2) Get the kit parts.....
                //    Use the item filter to hold the list of items we want, NOT the user's filters.
                $parameters['FILTER_ITEM'] = $kitPartsToGet;    // since it is an array, it will use an ' IN ()' clause
                $parameters['FILTER_ITEMGROUP'] = '';                // relax, we did a pushFilters() up above.....
                $parameters['FILTER_PRODUCTLINEID'] = '';

                $kitParts = QueryResult($this->buildSqlQuery($parameters, 'KIT_PARTS'));
                if ($kitParts === false) {
                    break;    // there is no error, but there were no kits
                }

                // 3) save the kit part information for later, so we can order enough parts to satisfy the kit itself
                // 3b) while we're here, see which of these kit parts we need to fetch.
                $itemsToGet = array();

                foreach ($kitParts as $kitPart) {
                    $itemID = $kitPart['ITEMID'];   // the kit id
                    $itemIDPart = $kitPart['PART'];     // the part id
                    // $itemToPart[$itemID][] = $itemIDPart;
                    $this->kitPartInformation[$itemIDPart][$itemID] = $kitPart['QUANTITY'] * $this->getConvFactorFromUOM($kitPart['UNIT'], $this->kitInfo[$itemID]['UOMGROUPKEY']);

                    if (($parameters['DIAGNOSE'] ?? false) === true) {
                        $this->diagnostics .= sprintf($itemContainsPartLocalizedStr, $itemID, $itemIDPart);
                    }
                    // do we need to fetch this kit part?
                    if (!isset($this->longestLeadTime[$itemIDPart])) {    // do we have this, or KNOW about this item id? (i.e. don't try to fetch an item more than once)
                        $this->longestLeadTime[$itemIDPart] = -1;         // well, we KNOW about this but we don't yet have it.  And don't know the longest lead time, which we want....
                        $itemsToGet[] = $itemIDPart;
                    }
                }

                // 4) ok, now lets get all the parts we don't have already,
                // along with THEIR vendors
                if (count($itemsToGet)) {
                    // Now we want to fetch the getItems list as if the customer asked for it....
                    $parameters['FILTER_ITEM'] = $itemsToGet;     // as an array, the code will get each of these with an ' IN ()' clause

                    // get the items from our list in $itemsToGet
                    // note: we may not get them all!  Some might be services, some not enabled for replenishment!
                    if (!$this->getItemList($parameters, $itemList, $warehouseList, $terms)) { // ADD ON to the item list
                        $ok = false;
                        break;
                    }

                    // AND, if any of these PARTS are kits, get THEM
                    if (!$this->getKitParts($parameters, $itemList, $warehouseList, $terms)) { // CURSES!  HE RECURSES!
                        $ok = false;
                        break;
                    }
                }
            }
        } while (false);    // do once (allow for breaks)

        // put back the parameters
        $this->popFilters($parameters);

        return $ok;
    }


    /**
     *      getForecastTableEntries - get all statistical entries from the as of date on to the future
     *
     * @param string $asOf
     */
    private function getForecastTableEntries($asOf)
    {
        $stmt = array();

        $stmt[0] = "SELECT itemid, warehouseid, effectivedate, quantity FROM replenishforecast WHERE cny#=:1 AND effectivedate >= :2 ORDER BY effectivedate";
        $stmt[1] = GetMyCompany();
        $stmt[2] = $asOf;

        $res = QueryResult($stmt);
        if ($res !== false) {
            $this->forecastTableEntries = [];
            foreach ($res as $entry) {
                if ( ! isset($entry['WAREHOUSEID']) || ($entry['WAREHOUSEID'] == '')) {
                    $entry['WAREHOUSEID'] = self::WAREHOUSE_PLACEHOLDER;   // no warehouse key?  Then placeholder string
                }
                $save = array(
                    'FUTURE_DAYS' => $this->cachedDateDiffInDays($asOf, $entry['EFFECTIVEDATE']),   // how far in the future is this?
                    'QUANTITY'    => $entry['QUANTITY'],
                );
                $this->forecastTableEntries[$entry['ITEMID']][$entry['WAREHOUSEID']][] = $save;
            }
        }
     }


    /**
     *      lookUpDemandValue - given an item and number of days to look out into the future,
     *              return the sum of the amounts, if any, where the item matches and the
     *              warehouse matches or was not specified on the account
     *              return is in BASE UNITS
     *
     * @param string $item
     * @param string $warehouse
     * @param int    $days
     *
     * @return int|float
     */
    private function lookUpDemandValue($item, $warehouse, $days)
    {
        // is the passed warehouse real?
        if (($warehouse == null) || ($warehouse == '')) {
            $warehouse = self::WAREHOUSE_PLACEHOLDER;   // no warehouse key?  Then placeholder string
        }

        // does the warehouse exist in the db?  If not, try the placeholder version
        if ( ! isset($this->forecastTableEntries[$item][$warehouse])) { // specific entries for this warehouse?
            $warehouse = self::WAREHOUSE_PLACEHOLDER;                   // ok, then, how about just item entries with NO warehouse?
        }

        $rtn = 0;
        if ( isset($this->forecastTableEntries[$item][$warehouse])) { // test warehouse or non-warehouse, as per above....
            foreach ($this->forecastTableEntries[$item][$warehouse] as $entry) {
                if ($entry['FUTURE_DAYS'] <= $days) {
                    $rtn += $entry['QUANTITY'];
                }
            }
        }
        return $rtn;
    }


    /**
     *      get Most Recent Vendor Purchase For Item - for each item, who did we buy it from most recently?
     *          we need this to sort the vendors into this order....
     *
     * @param string[] $parameters
     * @param array $itemList
     */
    private function getMostRecentVendorPurchaseForItem($parameters, &$itemList)
    {
        $lastPurchases = QueryResult($this->buildSqlQuery($parameters, 'LAST_PURCHASE_FROM'));
        if ($lastPurchases === false) {
            return;
        }

        $table = array();
        // these are sorted by item, then decreasing date.  So, the first vendor is the most recent one.
        //  however, sometimes you don't have a vendor in the vendor tables that was this most recent one,
        //  so we order the vendors by date, maybe without the most recent vendor.
        foreach ($lastPurchases as $row => $entry) {
            $table[$entry['ITEM']][ substr($entry['HDR_VENDORNAME'], 1)] = $row;    // remove the leading 'V' so it becomes a vendor ID.
        }

        foreach ($itemList as $warehouse => $warehouseList) {
            foreach ($warehouseList as $item => $itemEntry) {
                if (isset($table[$item])) {    // new item, not yet purchased?  Or do we have an entry for it?
                    foreach ($itemEntry['VENDORS'] as $vendorID => $vendorEntry) {                                      // or IS there a vendor?
                        $order = $table[$item][$vendorID] ?? PHP_INT_MAX;  // hopefully the highest we'll encounter
                        $itemList[$warehouse][$item]['VENDORS'][$vendorID]['MOST_RECENT'] = $order; // all the others are down the list
                    }
                }
            }
        }
    }


    /**
     *      fillInWarehouseItemVendorInfo - common helper to fill in the item/warehouse/vendor info table 'itemList'.
     *                      we read data from a couple of different sources and, rather than duplicating code, this is a common point of adding to the 'item list'.
     *
     * @param string   $warehouseID
     * @param string   $itemID
     * @param string[] $dataFromQuery
     * @param array    $itemList
     * @param string[] $terms                list of term names by record number
     * @param bool     $warehouseSpecific    the dataFromQuery is not from the more general item/vendor list
     */
    private function fillInWarehouseItemVendorInfo($warehouseID, $itemID, &$dataFromQuery, &$itemList, &$terms, $warehouseSpecific)
    {
        if ( ! isset($itemList[$warehouseID][$itemID])) {

            $this->longestLeadTime[$itemID] = 0;   // we have this item id, don't yet have the longest lead time

            if ( ! isset($dataFromQuery['ITEM_UNITS_OF_MEASURE'])) {
                $dataFromQuery['ITEM_UNITS_OF_MEASURE'] = $this->UOMGroups[$dataFromQuery['UOMGROUPKEY']]['DEFAULT_UNIT'];
            }
            $locationName = $this->getLocationNameFromRecordNumber($dataFromQuery['LOCATIONKEY']);
            $item = [
                'WAREHOUSE'             => $warehouseID,
                'WAREHOUSENAME'         => $dataFromQuery['WAREHOUSENAME'],
                'WAREHOUSEDIMKEY'       => $dataFromQuery['WAREHOUSEDIMKEY'],
                'SHIPTOKEY'             => $dataFromQuery['SHIPTOKEY'],       // record #.  Often empty/null/0
                'ITEM'                  => $itemID,
                'ITEMDIMKEY'            => $dataFromQuery['ITEMDIMKEY'],
                'ITEMNAME'              => $dataFromQuery['ITEMNAME'],
                'PRODUCTLINEID'         => $dataFromQuery['PRODUCTLINEID'],
                'LOCATIONKEY'           => $dataFromQuery['LOCATIONKEY'],
                'LOCATION_NAME'         => $locationName,
                'LOCATION'              => $locationName,   // for the UI to display
                'ITEMTYPE'              => $dataFromQuery['ITEMTYPE'],
                'MAX_ORDER_QTY'         => $dataFromQuery['W_MAX_ORDER_QTY'] ?? $dataFromQuery['I_MAX_ORDER_QTY'],   // prefer item-warehouse to item
                'UOMGROUPKEY'           => $dataFromQuery['UOMGROUPKEY'],
                'UOM_GROUP'             => $this->UOMGroups[$dataFromQuery['UOMGROUPKEY']]['NAME'],
                'ITEM_UNITS_OF_MEASURE' => $dataFromQuery['ITEM_UNITS_OF_MEASURE'],
                'ITEM_CONVFACTOR'       => $this->uomCache[$dataFromQuery['ITEM_UNITS_OF_MEASURE']][$dataFromQuery['UOMGROUPKEY']]
                                            ?? $this->getConvFactorFromUOM( $dataFromQuery['ITEM_UNITS_OF_MEASURE'], $dataFromQuery['UOMGROUPKEY'] ),
                'SAFETY_STOCK'          => ($dataFromQuery['SAFETY_STOCK']   ?? $dataFromQuery['I_SAFETY_STOCK']),
                'REORDER_POINT'         => ($dataFromQuery['REORDER_POINT']  ?? $dataFromQuery['I_REORDER_POINT']),
                'REORDER_QTY'           => ($dataFromQuery['REORDER_QTY']    ?? $dataFromQuery['I_REORDER_QTY']),
                'REPLENISHMENT_METHOD'  => $dataFromQuery['METHOD'] ?? ($dataFromQuery['I_METHOD'] ?? $this->getMethodFromPrefsIfNeedBe('')),

                'VENDORS'               => array(),
                'IWVLIST'               => false,       // to start with; were any item / warehouse / vendor records added here?
            ];

            // If we support DELIVER-TO at the line level, then set it.
            //  Otherwise skip all this work....
            if ($this->deliverToLine) {
                $shipTo = $this->getShipToRecFromKey($dataFromQuery['SHIPTOKEY']);
                if (isset($shipTo['CONTACT'])) {
                    $item['DELIVERTOKEY'] = $shipTo['CONTACTNAME']; // might be empty
                }
                if ($item['DELIVERTOKEY'] == '') {
                    $item['DELIVERTOKEY'] = $this->deliverToHeader;
                }
            }

            $itemList[$warehouseID][$itemID] = $item; // save
        }

        // If an item / warehouse record has vendors, we use those.  If not, we use the item / vendor list.
        // Note: item / warehouse / vendor records are ALL added before ANY item / vendor records.
        // So, here, if we are adding an item / vendor record, but the record has item warehouse vendors, don't add this vendor.
        if ( ($warehouseSpecific === false) && ($itemList[$warehouseID][$itemID]['IWVLIST'] === true)) {
            return;   // this warehouse was added by the item/warehouse/vendor list so we do not add to it.
        }

        // now fill in the vendor data, if there is some:
        if (isset($dataFromQuery['VENDOR']) && ($dataFromQuery['VENDOR'] != '')) {
            $vendorID = $dataFromQuery['VENDOR'];
            if ($dataFromQuery['UOM'] == '') {
                $dataFromQuery['UOM'] = $dataFromQuery['ITEM_UNITS_OF_MEASURE'];
                if ($dataFromQuery['UOM'] == '') { // still?
                    $dataFromQuery['UOM'] = $this->UOMGroups[$dataFromQuery['UOMGROUPKEY']]['DEFAULT_UNIT'];
                }
            }

            if (!isset($dataFromQuery['LEAD_TIME']) || ($dataFromQuery['LEAD_TIME'] == '')) {
                $dataFromQuery['LEAD_TIME'] = $dataFromQuery['V_LEAD_TIME'];  // if no lead time in the vendor TABLES, get the one from the vendor.
            }
            $vendorTermKey = (isset($dataFromQuery['V_TERMSKEY']) && ($dataFromQuery['V_TERMSKEY'] != '')) ? $dataFromQuery['V_TERMSKEY'] : $this->docpar['TERMKEY'];
            $term          = ($terms[$vendorTermKey] ?? '');
            if ($term == '') {
                return; // gotta have a term...
            }
            $vendor = array(
                'VENDORID'           => $vendorID,
                'VENDORDIMKEY'       => $dataFromQuery['VENDORDIMKEY'],
                'VENDORNAME'         => $dataFromQuery['VENDORNAME'],
                'STOCK_NUMBER'       => $dataFromQuery['STOCK_NUMBER'],
                'CURRENCY'           => $dataFromQuery['CURRENCY'],
                'LEAD_TIME'          => $dataFromQuery['LEAD_TIME'],
                'ECONOMIC_ORDER_QTY' => $dataFromQuery['ECONOMIC_ORDER_QTY'],
                'MIN_ORDER'          => $dataFromQuery['MIN_ORDER_QTY'],
                'UNITS_OF_MEASURE'   => $dataFromQuery['UOM'],
                'CONVFACTOR'         => $this->uomCache[$dataFromQuery['UOM']][$dataFromQuery['UOMGROUPKEY']] ?? $this->getConvFactorFromUOM( $dataFromQuery['UOM'], $dataFromQuery['UOMGROUPKEY'] ),
                'EXCHANGE_RATE'      => $dataFromQuery['EXCHANGE_RATE'],
                'CURRENCY_EXCHANGE'  => $this->currencyExchangeName,
                'CURRENCY_WARNINGS'  => $dataFromQuery['CURRENCY_WARNINGS'],
                'FUTURE_OE'          => 0,
                'FUTURE_PO'          => 0,
                'FUTURE_IC'          => 0,
                'KIT_NEEDS'          => 0,
                'VENDORTERM'         => $term,
                'TERMKEY'            => $vendorTermKey,
                'FORM1099TYPE'       => $dataFromQuery['FORM1099TYPE'],
                'FORM1099BOX'        => $dataFromQuery['FORM1099BOX'],
                'IV_ROWNUM'          => $dataFromQuery['IV_ROWNUM'],    // their fetch order, BEFORE the 'order by' clause
                'FORECAST_DEMAND_IN_LEAD_TIME' => $dataFromQuery['FORECAST_DEMAND_IN_LEAD_TIME'],
                'PREFERRED_VENDOR'   => $dataFromQuery['PREFERRED_VENDOR'],
            );

            if ($this->longestLeadTime[$itemID] < $dataFromQuery['LEAD_TIME']) {
                $this->longestLeadTime[$itemID] = $dataFromQuery['LEAD_TIME'];   // so far, this is the longest lead time for this item
            }
            $itemList[$warehouseID][$itemID]['VENDORS'][$vendorID] = $vendor;
            $itemList[$warehouseID][$itemID]['IWVLIST'] = $warehouseSpecific;   // so we know
        }
    }


    /**
     *  Set the exchange and rate to the one defined in the transaction definition, unless that one won't work for
     *      this vendor's currency.
     *
     * @param string[]   $values
     *
     * @return bool
     */
    private function setExchangeRateAndType(&$values)
    {
        $base = $this->getCurrencyForLocation($values['LOCATIONKEY']);
        if ($values['CURRENCY'] == '') {
            $values['CURRENCY'] = $base;
        }
        // no base currency?  No currencies at all? base and target currency the same?
        if ((IsMCPSubscribed() == false) || ($base == '') || ($values['CURRENCY'] == $base)) {
            $rate = 1.0; // well, the exchange rate will be 1
        } else {
            $curr = $values['CURRENCY'];
            $date = $values['EXCHANGE_DATE'];
            static $cache = [];
            static $warnings = [];
            if (isset($cache[$base][$curr][$date])) {
                $rate = $cache[$base][$curr][$date];
                $values['CURRENCY_WARNINGS'] = $warnings[$base][$curr][$date];
            } else {
                $rate = $this->getExchangeRate($base, $curr, $values['EXCHANGE_DATE'], $values['CURRENCY_EXCHANGE'], $values['CURRENCY_WARNINGS']);
                $cache[$base][$curr][$date] = $rate;
                $warnings[$base][$curr][$date] = $values['CURRENCY_WARNINGS'];
            }
            if ($rate === false) {
                // UPDATE: 11/9/2018 Shilpa decided she wants the vendor to show even though it has no exchange rate,
                //      and even though you will NOT be able to create a PO for it.  This seems like the only place
                //      where we allow people to try to create a PO when we KNOW it won't work.....
                //return false;     // warnings already thrown

                $rate = 1.0;        // this is wrong, but the math works and PO generation will kick it out when IT looks for the exchange rate.  Man, this is awful!

                // However, let's pull some shenanegans!  Set the ROW NUMBER to a high number so that the vendor tends to sort to the bottom of the list....
                $values['IV_ROWNUM'] = PHP_INT_MAX; // well, this may at least give the txn a chance to work with some other vendor
            }
        }
        $values['EXCHANGE_RATE'] = (float)$rate;
        $values['BASE']          = $base;
        return true;
    }


    /**
     *      Get the list of vendors for item/warehouses; these supercede any item/vendor list items
     *
     * @param  string[]  $parameters
     * @param  array     $itemList         the list of items, by item.  We add any found warehouse/vendors to it.
     * @param string[]  $terms             list of term names by record number
     *
     * @return bool
     */
    private function getItemWarehouseVendorList($parameters, &$itemList, &$terms)
    {
        $needVendorSearchForItemWarehouse = array();

            // get the item warehouse list, as they don't all have vendors
        $itemWarehouse = QueryResult($this->buildSqlQuery($parameters, 'ITEM_WAREHOUSE'));
        if ($itemWarehouse !== false) {
            foreach ($itemWarehouse as $iw) {
                $this->fillInWarehouseItemVendorInfo($iw['WAREHOUSE'], $iw['ITEM'], $iw, $itemList,  $terms, true);
                $needVendorSearchForItemWarehouse[$iw['ITEMWHSEKEY']] = ['WAREHOUSE' => $iw['WAREHOUSE'], 'ITEM' => $iw['ITEM']];  // maybe, ya
            }

            if ((($parameters['DIAGNOSE'] ?? false) === true) && empty($itemWarehouse)) {
                $item = $parameters['FILTER_ITEM'];
                if (is_array($item)) {
                    $item = implode(',', $item);
                    $tokens = [
                        [
                            'id' => 'IA.ITEMS_ARE_NOT_IN_ITEMWAREHOUSE_TABLE',
                            'placeHolders' => [
                                ['name' => 'ITEMS', 'value' => $item]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $this->diagnostics .= GT($text, 'IA.ITEMS_ARE_NOT_IN_ITEMWAREHOUSE_TABLE');
                } else {
                    $tokens = [
                        [
                            'id' => 'IA.ITEM_IS_NOT_IN_ITEMWAREHOUSE_TABLE',
                            'placeHolders' => [
                                ['name' => 'ITEM', 'value' => $item]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $this->diagnostics .= GT($text, 'IA.ITEM_IS_NOT_IN_ITEMWAREHOUSE_TABLE');
                }
            }
        }

            // get item warehouse vendor data
        $itemWarehouseVendors = QueryResult($this->buildSqlQuery($parameters, 'ITEM_WAREHOUSE_VENDOR'));
        if ($itemWarehouseVendors !== false) {
            foreach ($itemWarehouseVendors as $iw) {

                if (isset($iw['VENDOR'])) {
                    $iw['EXCHANGE_DATE'] = $parameters['TRANSACTION_DATE'];
                    if ( ! $this->setExchangeRateAndType($iw)) {
                        // QA decision: ignore errors here, but toss the vendor/item/warehouse combo.
                        continue;
                        //return false;
                    }
                }

                // Fill in the item list with the data we got from sql
                $this->fillInWarehouseItemVendorInfo($iw['WAREHOUSE'], $iw['ITEM'], $iw, $itemList, $terms, true);
                unset($needVendorSearchForItemWarehouse[$iw['ITEMWHSEKEY']]);  // no, we got at least one
            }
            if ((($parameters['DIAGNOSE'] ?? false) === true) && empty($itemWarehouseVendors)) {
                $item = $parameters['FILTER_ITEM'];
                if (is_array($item)) {
                    $item = implode(',', $item);
                    $tokens = [
                        [
                            'id' => 'IA.ITEMS_ARE_NOT_IN_ITEMWAREHOUSEVENDOR_TABLE',
                            'placeHolders' => [
                                ['name' => 'ITEMS', 'value' => $item]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $this->diagnostics .= GT($text, 'IA.ITEMS_ARE_NOT_IN_ITEMWAREHOUSEVENDOR_TABLE');
                } else {
                    $tokens = [
                        [
                            'id' => 'IA.ITEM_IS_NOT_IN_ITEMWAREHOUSEVENDOR_TABLE',
                            'placeHolders' => [
                                ['name' => 'ITEM', 'value' => $item]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $this->diagnostics .= GT($text, 'IA.ITEM_IS_NOT_IN_ITEMWAREHOUSEVENDOR_TABLE');
                }
            }
        }

        // Does this item/warehouse info have vendors, but they're filtered out (by specific vendor or currency, for example)?
        // in that case, do NOT get regular item/vendor vendors, because the customer said she only wants THESE vendors....
        if (count($needVendorSearchForItemWarehouse) > 0) {

            $stmt = array();
            $stmt[0] = "SELECT iw.record# ITEMWHSEKEY FROM ICITEMWHSE iw
                          WHERE EXISTS (
                              SELECT 1 FROM ICITEMVENDOR iv WHERE iv.CNY# = :1 AND iv.ITEMWHSEKEY = iw.record#
                              ) 
                          AND   iw.CNY# = :1";

            $stmt[1] = GetMyCompany();
            $stmt = PrepINClauseStmt($stmt, array_keys($needVendorSearchForItemWarehouse), ' AND iw.record# ' );
            $res = QueryResult($stmt);
            if ($res !== false) {
                foreach ($res as $row) {

                    $warehouseID = $needVendorSearchForItemWarehouse[$row['ITEMWHSEKEY']]['WAREHOUSE'];
                    $itemID      = $needVendorSearchForItemWarehouse[$row['ITEMWHSEKEY']]['ITEM'];

                    // flag that we have vendors, even though we don't, so we don't get generic item/vendor vendors
                    $itemList[$warehouseID][$itemID]['IWVLIST'] = true;
                }
            }
        }
        return true;
    }


    /**
     *      Get the list of vendors for items; glue them onto the item list passed in.
     *  Glue one per warehouse, which is a lot of repetition but makes the return value easier
     *  to make
     *
     * @param  string[]  $parameters
     * @param  array     $itemList          the list of items, by item.  We add any found vendors to it.  Per warehouse
     * @param   array    $warehouseList     list of all warehouses doing replenishment
     * @param string[]   $terms             list of term names by record number
     *
     * @return bool
     */
    private function getItemVendorList($parameters, &$itemList, $warehouseList, &$terms)
    {
        $optIn = ($this->inventoryPrefs['REPLENISH_OPT_IN'] === 'T');

        $itemVendors = QueryResult($this->buildSqlQuery($parameters, 'ITEM_VENDOR'));
        if ($itemVendors === false) {
            return false;
        }
        // Blend the vendors and warehouses into the item list; it might be empty!
        foreach ($itemVendors as &$iv) {
            $itemID = $iv['ITEM'];

            $iv['EXCHANGE_DATE'] = $parameters['TRANSACTION_DATE'];

            if ($this->setExchangeRateAndType($iv) === false) {
                // QA decision: ignore errors here, but toss the vendor/item/warehouse combo.
                continue;
                //return false;
            }

            // duplicate the data per warehouse
            $itemIsRequiredInItemWarehouseLocalizedStr = null;
            $itemsAreRequiredInItemWarehouseLocalizedStr = null;
            foreach ($warehouseList as $warehouseID => $warehouse) {

                // if the item/warehouse pair exists already,
                //      and there are vendors (even if they were filtered out),
                //  then we don't need to add these vendors to the existing item/warehouse.
                if (isset($itemList[$warehouseID][$itemID])) {
                    if ($itemList[$warehouseID][$itemID]['IWVLIST'] === true) {
                        continue;
                    }
                } else if ($optIn) {
                    // If we're set for OPT-IN, and we don't already have the item/warehouse
                    //  from the item/warehouse pass, then there's no point in going farther.
                    if (($parameters['DIAGNOSE'] ?? false) === true) {
                        if (!$itemIsRequiredInItemWarehouseLocalizedStr) {
                            $tokens = [
                                [
                                    'id' => 'IA.ITEM_IS_REQUIRED_IN_ITEMWAREHOUSE_TABLE',
                                    'placeHolders' => [
                                        ['name' => 'ITEM', 'value' => "\'%1s\'"]
                                    ]
                                ],
                                [
                                    'id' => 'IA.ITEMS_ARE_REQUIRED_IN_ITEMWAREHOUSE_TABLE',
                                    'placeHolders' => [
                                        ['name' => 'ITEMS', 'value' => "\'%1s\'"]
                                    ]
                                ]
                            ];
                            $text = getLocalizedTextWithThrow($tokens);
                            $itemIsRequiredInItemWarehouseLocalizedStr = GT($text, 'IA.ITEM_IS_REQUIRED_IN_ITEMWAREHOUSE_TABLE');
                            $itemsAreRequiredInItemWarehouseLocalizedStr = GT($text, 'IA.ITEMS_ARE_REQUIRED_IN_ITEMWAREHOUSE_TABLE');
                        }

                        $item = $parameters['FILTER_ITEM'];
                        if (is_array($item)) {
                            $item = implode(',', $item);
                            $this->diagnostics .= sprintf($itemsAreRequiredInItemWarehouseLocalizedStr, $item);
                        } else {
                            $this->diagnostics .= sprintf($itemIsRequiredInItemWarehouseLocalizedStr, $item);
                        }
                    }
                    continue;
                }

                // If we get an exchange rate failure for one warehouse, no point in trying
                // for the other warehouses; exchange rates are all about the vendor and TD.
                    $iv['LOCATIONKEY'] = $warehouse['LOCATIONKEY']; // we didn't get these from the query above
                    $iv['WAREHOUSENAME'] = $warehouse['WAREHOUSENAME'];
                    $iv['WAREHOUSEDIMKEY'] = $warehouse['WAREHOUSEDIMKEY'];
                    $iv['SHIPTOKEY'] = $warehouse['SHIPTOKEY'];
                    $iv['REORDER_QTY'] = $warehouse['I_REORDER_QTY']; // take the item version since there is no item/warehouse record

                    if ($this->setExchangeRateAndType($iv) === false) {
                        // QA decision: ignore errors here, but toss the vendor/item/warehouse combo.
                        continue;
                        //return false;
                    }

                    // Fill in the item list with the data we got from sql
                    $this->fillInWarehouseItemVendorInfo($warehouseID, $itemID, $iv, $itemList, $terms, false);
            }
        }

        if ((($parameters['DIAGNOSE'] ?? false) === true) && empty($itemVendors)) {
            $item = $parameters['FILTER_ITEM'];
            if (is_array($item)) {
                $item = implode(',', $item);
                $tokens = [
                    [
                        'id' => 'IA.ITEMS_ARE_NOT_IN_ITEMVENDOR_TABLE',
                        'placeHolders' => [
                            ['name' => 'ITEMS', 'value' => $item]
                        ]
                    ]
                ];
                $text = getLocalizedTextWithThrow($tokens);
                $this->diagnostics .= GT($text, 'IA.ITEMS_ARE_NOT_IN_ITEMVENDOR_TABLE');
            } else {
                $tokens = [
                    [
                        'id' => 'IA.ITEM_IS_NOT_IN_ITEMVENDOR_TABLE',
                        'placeHolders' => [
                            ['name' => 'ITEM', 'value' => $item]
                        ]
                    ]
                ];
                $text = getLocalizedTextWithThrow($tokens);
                $this->diagnostics .= GT($text, 'IA.ITEM_IS_NOT_IN_ITEMVENDOR_TABLE');
            }
        }

        return true;
    }


    /**
     *      Get the list of stockable kits; they may have been fetched before if they have ever been
     *  purchased.  If not, there may be no vendor/warehouse info.  We do this separately from getKitParts
     *  because that is driven off kits with warehouses, which means you've bought or sold one.  Here we
     *  catch the FIRST one, where you have a sales order but haven't actually sold it yet.
     *
     * @param  string[]  $parameters
     *
     * @return bool
     */
    private function getStockableKits($parameters)
    {
        $sk = QueryResult($this->buildSqlQuery($parameters, 'GET_KITS'));
        if ($sk === false) {
            return false;
        }
        foreach ($sk as $kit) {
            $itemID                 = $kit['ITEM'];
            $this->kitInfo[$itemID] = $kit;                 // save for later
        }
        return true;
    }


    /**
    *      Get the list of possible warehouses; those that are enabled for replenishment.
    *
    * @param  string[]  $parameters
    *
    * @return array
    */
    private function getWarehouseList($parameters)
    {
        $rtn = array();
        $warehouses = QueryResult($this->buildSqlQuery($parameters, 'WAREHOUSES'));
        if (($warehouses !== false) && (count($warehouses) > 0)) {
            foreach ($warehouses as $warehouse) {
                $rtn[$warehouse['WAREHOUSE']] = $warehouse;
            }
        } else {
            // the location key is either an array, or an empty string.
            // an array means the customer specified a specific location; else they didn't.
            if (is_array($parameters['FILTER_LOCATIONKEY']) && (count($parameters['FILTER_LOCATIONKEY']) > 0)) {
                Globals::$g->gErr->addIAError('INV-0241', __FILE__ . ':' . __LINE__,
                    "No warehouses in the location are enabled for replenishment.",[]);
            } else {
                Globals::$g->gErr->addIAError('INV-0242', __FILE__ . ':' . __LINE__,
                    "No warehouses are enabled for replenishment.",[]);
            }
        }
        return $rtn;
    }



    /**
     *      Get the ON-HAND, ON-ORDER, and ON-HOLD amounts
     *
     * @param  string[]  $parameters
     * @param  array     $itemList
     *
     */
    private function getHistoricalTransactions($parameters, &$itemList)
    {
        // Turns out our 'on hand' functionality is broken, so Senthil suggested using item-hist-cost for quantity on hand...
        $queryArray = $this->buildSqlQuery($parameters, 'GET_ONHAND');

        $queryArray[0] = " SELECT * FROM ( "
            . $queryArray[0]
            . ") WHERE ason = max_ason ";

        $itemWarehouses = QueryResult($queryArray);
        if ($itemWarehouses !== false) {
            foreach ($itemWarehouses as $iw) {
                $itemID = $iw['ITEM'];
                $warehouse = $iw['WAREHOUSE'];
                // Might be for an item we have, or a kit, or an item we don't care about.
                if (isset($itemList[$warehouse][$itemID])) {
                    $itemList[$warehouse][$itemID]['CURRENT_ON_HAND'] = $iw['ONHAND'] + 0.0;
                }
                // hm, for our kit friends, do we have THEIR info?
                if (isset($this->kitInfo[$itemID])) {
                    $this->kitInfo[$itemID]['WAREHOUSES'][$warehouse]['CURRENT_ON_HAND'] = $iw['ONHAND'] + 0.0;
                }
            }
        }

        if ((($parameters['DIAGNOSE'] ?? false) === true) && empty($itemWarehouses)) {
            $item = $parameters['FILTER_ITEM'];
            if (is_array($item)) {
                $item = implode(',', $item);
                $tokens = [
                    [
                        'id' => 'IA.ITEMS_HAVE_NO_HISTORICAL_ONHAND_TRANSACTIONS',
                        'placeHolders' => [
                            ['name' => 'ITEMS', 'value' => $item]
                        ]
                    ]
                ];
                $text = getLocalizedTextWithThrow($tokens);
                $this->diagnostics .= GT($text, 'IA.ITEMS_HAVE_NO_HISTORICAL_ONHAND_TRANSACTIONS');
            } else {
                $tokens = [
                    [
                        'id' => 'IA.ITEM_HAS_NO_HISTORICAL_ONHAND_TRANSACTIONS',
                        'placeHolders' => [
                            ['name' => 'ITEM', 'value' => $item]
                        ]
                    ]
                ];
                $text = getLocalizedTextWithThrow($tokens);
                $this->diagnostics .= GT($text, 'IA.ITEM_HAS_NO_HISTORICAL_ONHAND_TRANSACTIONS');
            }
        }

        // And we use the older on-hand/on-hold/on-order for everything BUT on-hand.
        $itemWarehouses = QueryResult($this->buildSqlQuery($parameters, 'PAST_ACTIVITY'));
        if ($itemWarehouses !== false) {
            foreach ($itemWarehouses as $iw) {
                $itemID = $iw['ITEM'];
                $warehouse = $iw['WAREHOUSE'];
                // Might be for an item we have, or a kit, or an item we don't care about.
                if (isset($itemList[$warehouse][$itemID])) {
                    $itemList[$warehouse][$itemID]['CURRENT_ON_ORDER'] = $iw['ONORDER'];  // would it be faster to make a new array and merge it in?
                    $itemList[$warehouse][$itemID]['CURRENT_ON_HOLD']  = $iw['ONHOLD'];
                }
                // and again, for our kit friends, do we have THEIR info?
                if (isset($this->kitInfo[$itemID])) {
                    $this->kitInfo[$itemID]['WAREHOUSES'][$warehouse]['CURRENT_ON_ORDER'] = $iw['ONORDER'];
                    $this->kitInfo[$itemID]['WAREHOUSES'][$warehouse]['CURRENT_ON_HOLD']  = $iw['ONHOLD'];
                }
            }
            if ((($parameters['DIAGNOSE'] ?? false) === true) && empty($itemWarehouses)) {
                $item = $parameters['FILTER_ITEM'];
                if (is_array($item)) {
                    $item = implode(',', $item);
                    $tokens = [
                        [
                            'id' => 'IA.ITEMS_HAVE_NO_HISTORICAL_ONORDER_OR_ONHOLD_TRANSACTION',
                            'placeHolders' => [
                                ['name' => 'ITEMS', 'value' => $item]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $this->diagnostics .= GT($text, 'IA.ITEMS_HAVE_NO_HISTORICAL_ONORDER_OR_ONHOLD_TRANSACTION');
                } else {
                    $tokens = [
                        [
                            'id' => 'IA.ITEM_HAS_NO_HISTORICAL_ONORDER_OR_ONHOLD_TRANSACTION',
                            'placeHolders' => [
                                ['name' => 'ITEM', 'value' => $item]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $this->diagnostics .= GT($text, 'IA.ITEM_HAS_NO_HISTORICAL_ONORDER_OR_ONHOLD_TRANSACTION');
                }
            }
        }
    }


    /**
     *  cachedDateDiffInDays return the diff in days from the base date to the test date.
     *          I cache both the base and test dates because we expect ONE base date (the as-of),
     *          and a set of test dates fronm the as-of to, say, 30 days later (well, a relatively short time).
     *          and there could be many many times the number of tests than there are days, so....
     *          (and date routines are hideously slow)
     *
     * @param string $baseDate
     * @param string $testDate
     *
     * @return string
     */
    function cachedDateDiffInDays($baseDate, $testDate)
    {
        static $cachedBaseDate = "";
        static $cache = null;

        if ($cachedBaseDate != $baseDate) {
            $cachedBaseDate  = $baseDate;
            $cache           = null;     // and reset the cache
        }

        if ( ! isset($cache[$testDate])) {
            $cache[ $testDate ] = DateDiff( $testDate, $cachedBaseDate );   // slow when called thousands of times.
        }
        return $cache[ $testDate ];
    }




    /**
     *      Get the ON-HAND, ON-ORDER, and ON-HOLD amounts for the future (AFTER AS-OF) and update the item list with them
     *
     *  USUALLY, the as-of date is today or not far in the past.  So we don't expect a LOT of records from the table.
     *
     * @param  string[]  $parameters
     * @param  array     $itemList
     *
     */
    private function updateListWithFututreTransactions($parameters, &$itemList)
    {
        // TODO: The On Hand numbers are not accurate, as per Senthil.  But, getting On Hand from the item hist cost table
        //          does not allow me to connect the changes to a specific transaction, only gives me a day summary.
        //          so, for now, I'm going to 'trust' the future numbers and we'll have to revisit how to do this better.

        $selects = "ict.name           as NAME,
                    ia.whencreated     as ASOF,
                    ia.quantity        as QUANTITY";

        $queryArray = $this->buildSqlQuery( $parameters, 'FUTURE_ACTIVITY', $selects );

        // note for Supplies Inventory: ONHOLD is going to be zero, since we don't 'sell' the items.
        // we could maybe figure out a better proxy, but....
        $queryArray[0] .= " AND ict.name  IN ('ONHAND', 'ONHOLD', 'ONORDER') ";

        $txns = QueryResult($queryArray);
        if ($txns !== false) {
            //  for each item/warehouse/vendor combo,
            //      take the lead time, compute the ON HAND, ON ORDER, ON HOLD for each type of txn (S,P,I)
            //      save it into the vendor info

            // First, lets set up the returned data in a format we like....
            $startDate = $parameters['FILTER_ASOFDATE'];
            $txnList = array();
            foreach ($txns as $txn) {
                $txnList[$txn['SPI']][] = array(
                    'WAREHOUSE'  => $txn['WAREHOUSE'],
                    'ITEM'       => $txn['ITEM'],
                    'NAME'       => $txn['NAME'],
                    'DAYS_AHEAD' => $this->cachedDateDiffInDays($startDate, $txn['ASOF']),
                    'QUANTITY'   => $txn['QUANTITY']
                );
            }

            $spi = array('S' => 'FUTURE_OE', 'P' => 'FUTURE_PO', 'I' => 'FUTURE_IC'); // which txn types go into which buckets?

            // Often there may be NO future records (as-of == today), or if the as-of is only a day or two past,
            // there may only be a handful of records.  So, lets loop through the found records FIRST, so we don't
            // loop through most of the item list....

            foreach ($spi as $type => $storeAs) {   // 'S', 'P', 'I'
                foreach (($txnList[$type] ?? []) as $spiCounts) {  // likely very few of these.....
                    $warehouseName = $spiCounts['WAREHOUSE'];
                    $itemID = $spiCounts['ITEM'];
                    if (isset($itemList[$warehouseName][$itemID])) {    // an item we have?
                        foreach ($itemList[$warehouseName][$itemID]['VENDORS'] as $vendorID => $vendor) {
                            $leadTime = $vendor['LEAD_TIME'];
                            if ($spiCounts['DAYS_AHEAD'] <= $leadTime) {
                                if ($spiCounts['NAME'] == 'ONHOLD') {       // subtract becase they've been sold
                                    $itemList[$warehouseName][$itemID]['VENDORS'][$vendorID][$storeAs] -= $spiCounts['QUANTITY'];
                                } else {                                    // otherwise add
                                    $itemList[$warehouseName][$itemID]['VENDORS'][$vendorID][$storeAs] += $spiCounts['QUANTITY'];
                                }
                            }
                        }
                    }

                    // and for our kit friends, see if they need updating...
                    if (isset($this->kitInfo[$itemID])) {
                        $leadTime = $this->longestLeadTime[$itemID] ?? 0;   // should be there by now, I hope! (we read all the parts for all the vendors, so should have this)
                        // logFL("***** Kits: lead time is $leadTime when looking at futures,");
                        if ($spiCounts['DAYS_AHEAD'] <= $leadTime) {
                            $this->kitInfo[$itemID]['WAREHOUSES'][$warehouseName][$storeAs] = (($spiCounts['NAME'] == 'ONHOLD') ? (- $spiCounts['QUANTITY']) : (+ $spiCounts['QUANTITY']));
                        }
                    }
                }

            }
            if ((($parameters['DIAGNOSE'] ?? false) === true) && empty($txns)) {
                $item = $parameters['FILTER_ITEM'];
                if (is_array($item)) {
                    $item = implode(',', $item);
                    $tokens = [
                        [
                            'id' => 'IA.ITEMS_HAVE_NO_FUTURE_TRANSACTION',
                            'placeHolders' => [
                                ['name' => 'ITEMS', 'value' => $item]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $this->diagnostics .= GT($text, 'IA.ITEMS_HAVE_NO_FUTURE_TRANSACTION');
                } else {
                    $tokens = [
                        [
                            'id' => 'IA.ITEM_HAS_NO_FUTURE_TRANSACTION',
                            'placeHolders' => [
                                ['name' => 'ITEM', 'value' => $item]
                            ]
                        ]
                    ];
                    $text = getLocalizedTextWithThrow($tokens);
                    $this->diagnostics .= GT($text, 'IA.ITEM_HAS_NO_FUTURE_TRANSACTION');
                }
            }
        }
    }


    /**
     * @param int|string $shiptokey   the record number of the shipto record
     *
     * @return array   the ship-to record
     */
    private function getShipToRecFromKey($shiptokey)
    {
        // PHP8_NUMERIC_STRING_COMPARE; Priority: medium; Behavior: same, Risk: low, Solution: php7eq0
        if ( Util::php7eq0($shiptokey) ) {
            return [];
        }

        // cache these as there are lots of dups
        static $cache = array();

        if ( ! isset($cache[$shiptokey])) {
            $cache[$shiptokey] = $this->contactMgr->GetHeadByRecordNo($shiptokey);
        }

        return $cache[$shiptokey];
    }


    /**
     *  Get the pricing information per vendor
     *
     * @param string[]  $parameters
     * @param array     $snapshotData     the flattened replenishDetail records with everything but price/extended price filled in.
     *
     */
    private function getPricing($parameters, &$snapshotData)
    {
        // This is going to be slow!
        // We could take shortcuts perhaps, but that assumes a lot of knowledge about how pricing works.

        // First step, go from item/warehouse/vendor to a-thing-that-can-be-priced
        $pricingUnit = array();
        foreach ($snapshotData as $index => $row) {

            if ($row['QUANTITY_TO_PURCHASE'] > 0) {
                $pricingUnit[$row['VENDORID']][$row['SHIPTOKEY']][$row['ITEM']][$row['QUANTITY_TO_PURCHASE']][] = $index;
            }
        }

        // The pricing handler refers to approval rule and policy manager A LOT.  Use this cache to cut down on the work....
        ApprovalRuleManager::$enableRuleCache     = true;
        ApprovalPolicyManager::$enablePolicyCache = true;
        $uomInfo = [];

        // Now, for each vendor and item, get the price
        foreach ($pricingUnit as $vendorID => $vendor) {
            foreach ($vendor as $shiptokey => $shipTo) {
                $shipToRec = $this->getShipToRecFromKey($shiptokey);
                $priceParams = $this->pricingHandler->PrepParams($vendorID, '', $shipToRec['CONTACTNAME'], $parameters['FILTER_ASOFDATE'], 'po');
                foreach ($shipTo as $itemID => $quantities) {
                    foreach ($quantities as $qtyToPurchase => $indexes) {
                        $item = $snapshotData[$indexes[0]];  // all of the lines in $indexes are for the same item id (item record)
                        // Now update each row with the same item/vendor/ship-to
                        foreach ($indexes as $index) {
                            $uomInfo['CONVFACTOR'] = $snapshotData[$index]['CONVFACTOR'] ?: ($item['ITEM_CONVFACTOR'] ?: 1.0);   // needed by the discount code
                            // Pricing can come from the transaction type (thus docpar is needed), vendor by item, product lines, quantity discounts, etc.
                            $price = $this->pricingHandler->SuggestPrice($priceParams, $itemID, $item['PRODUCTLINEID'], ($qtyToPurchase * $uomInfo['CONVFACTOR']), $this->docpar, $item['CURRENCY'], $priceMissing);
                            $snapshotData[$index]['PRICEMISSING'] = $priceMissing ? 'true' : 'false';
                            if ($this->docpar['DISCOUNT_ON_EXTENDEDPRICE'] != 'T') {
                                $snapshotData[$index]['DISCOUNTPERCENT'] = $priceParams['CONTACT']['DISCOUNT'];
                                // LATER, AS PER HARPREET: $this->pricingHandler->applyDiscount($snapshotData[$index], $price, $uomInfo, $this->defaultPrecisionForPO);
                                // WHEN WE DO DISCOUNTS, THEN DON'T DO THESE LINES...
                                // PHP8_NUMERIC_STRING_COMPARE; Priority: low; Behavior: same, Risk: low, Solution: php7eqEmptyStr
                                if ( !Util::php7eqEmptyStr($price) && !empty($uomInfo['CONVFACTOR'])) {
                                    $price = ibcmul($price, $uomInfo['CONVFACTOR'], $this->defaultPrecisionForPO, true);
                                }
                                $snapshotData[$index]['TRX_PRICE'] = $price;
                                // ************************* END OF LINES TO REMOVE WHEN DOING DISCOUNTS
                            } else {
                                if ($price != '' && !empty($uomInfo['CONVFACTOR'])) {
                                    $price = ibcmul($price, $uomInfo['CONVFACTOR'], $this->defaultPrecisionForPO, true);
                                }
                                $snapshotData[$index]['TRX_PRICE'] = $price;
                            }
                            $snapshotData[$index]['PURCHASE_PRICE'] = $snapshotData[$index]['TRX_PRICE'];
                            $this->replenishDetailMgr->generateCalculatedFields( $snapshotData[$index] ); // get computed fields
                        }
                    }
                }
            }
        }
    }



    /**
     *  ripple Out Kit Needs - We have a list of KITS and their parts.
     *          The kits themselves have needs (how many kits we expect to need)
     *          and so we need to influence all the items that make up the kit PARTS
     *
     *          The way I've organized this is for the individual items, which are likely parts, to ask
     *          if there is anything to be done to them
     *
     * @param string $itemID    the kit PART (not the kit itself)
     * @param string $warehouse the warehouse
     * @param array $item       One ROW of the item list.  The one wanting to be updated if need be.  The item list is one item's vendors and other data
     *
     */
    private function rippleOutKitNeeds($itemID, $warehouse, &$item)
    {
        // This is called once for EVERY kit part, though if it does get called for non-parts, that works too.
        foreach ($this->kitPartInformation[$itemID] as $kitID => $numberOfPartsNeededInbaseUnits) {

            if (isset($this->kitInfo[$kitID])) {

                $stockableKit = $this->kitInfo[$kitID];

                if (isset($stockableKit['RESULTS'][$warehouse])) {
                    $quantityToOrderInBaseUnits = $stockableKit['RESULTS'][$warehouse];
                } else {

                    $warehouseAvailable = false;
                    if (isset($stockableKit['WAREHOUSES'][$warehouse])) {
                        $warehouseAvailable = true;
                    }

                    //  $kit['I_SAFETY_STOCK'];

                    // we just want the quantity we need to order, in base units.
                    $method = ReplenishDetailManager::getInternalSalesForecastMethod($stockableKit['I_METHOD'] ?? '');
                    $itemUnits = $stockableKit['ITEM_CONVFACTOR'];
                    if (($stockableKit['I_METHOD'] == '') && ($method == 'FORECAST_DEMAND')) {
                        $method = 'REORDER_POINT';  // because a kit can't be FORECAST DEMAND, so give it SOMETHING
                    }

                    switch ($method) {
                        case 'FORECAST_TABLE':
                            $futureDemand = $this->lookUpDemandValue($itemID, $warehouse, $this->longestLeadTime[$itemID]);
                            break;

                        case 'REORDER_POINT':
                            $futureDemand = ($stockableKit['I_REORDER_POINT'] ?? 0) * $itemUnits;
                            break;

                        case 'FORECAST_DEMAND': // this is a vendor-based field, and we have no vendors for stockable kits
                            $futureDemand = 1;  // TODO: fixme.  But a kit part isn't a kit....
                            break;

                        default:
                            throw new Exception("Method '" . $stockableKit['I_METHOD'] . "' is not a valid REPLENISHMENT_METHOD for kit $itemID / $warehouse.");
                    }

                    $futures = 0;
                    if ($warehouseAvailable && ($method != 'REORDER_POINT')) {   // Shilpa and Tom say we shouldn't consider these for reorder-point
                        $futures = iround(
                            $stockableKit['WAREHOUSES'][$warehouse]['FUTURE_PO']
                            + $stockableKit['WAREHOUSES'][$warehouse]['FUTURE_OE']
                            + $stockableKit['WAREHOUSES'][$warehouse]['FUTURE_IC'],
                            0);
                    }

                    $currentOnHand = 0;
                    if ($warehouseAvailable) {
                        // onhold comes in as negative, so we add it to onhand+onorder
                        $currentOnHand = iround(
                            ($stockableKit['WAREHOUSES'][$warehouse]['CURRENT_ON_HAND']
                            + $stockableKit['WAREHOUSES'][$warehouse]['CURRENT_ON_ORDER'])
                            - $stockableKit['WAREHOUSES'][$warehouse]['CURRENT_ON_HOLD'],
                            0);
                    }

                    $quantityToOrderInBaseUnits =
                        iround(
                            $futureDemand
                            + ($stockableKit['I_SAFETY_STOCK'] * $itemUnits),
                            0)
                        - $futures
                        - $currentOnHand
                        ;

                    $t = $stockableKit['I_REORDER_QTY'] ? ($stockableKit['I_REORDER_QTY'] * $itemUnits) : 0; // now in base units
                    if (($method == 'REORDER_POINT') &&
                        ($t > 0) &&
                        ($quantityToOrderInBaseUnits > 0) &&
                        ($quantityToOrderInBaseUnits < $t)) {
                        $quantityToOrderInBaseUnits = $t;   // order this many
                    }

                    /* ***** max order quantity shouldn't apply to stockable kits, right?  You don't order them specifically
                    if ($quantityToOrderInBaseUnits > 0) {
                        if (isset($stockableKit['I_MAX_ORDER_QTY']) && ($stockableKit['I_MAX_ORDER_QTY'] > 0)) {          // is in base units
                            $t = $stockableKit['I_MAX_ORDER_QTY'] * $itemUnits; // now in base units
                            if ($quantityToOrderInBaseUnits > $t) {
                                $quantityToOrderInBaseUnits = $t;
                            }
                        }
                    }
                    **** */

                    $this->kitInfo[$kitID]['RESULTS'][$warehouse] = $quantityToOrderInBaseUnits;
                }

                $needToPurchase = $numberOfPartsNeededInbaseUnits * $quantityToOrderInBaseUnits;
                foreach ($item['VENDORS'] as &$vendor) {
                    $vendor['KIT_NEEDS'] += $needToPurchase;
                }
            }
        }
    }



    /**
     *  flatten Array And Finish Records - take the 'item list' which has item/warehouses and an array of vendors, and make one record PER item/warehouse/vendor
     *              Also, fill in the warehouse/item group field, and the proposed po field.
     *              If we're using SHIP-TO and not DELIVER-TO, then there should be one PO per vendor per SHIP-TO location.
     *              But, if we're using DELIVER-TO, then there should be one PO per vendor.
     *
     * @param string[]  $parameters
     * @param array     $itemList
     *
     * @return array    the finished data ready to be saved as a snapshot or sent back to the UI
     */
    private function flattenArrayAndFinishRecords($parameters, &$itemList)
    {
        $rtn            = array();
        $showAllItems   = ($parameters['SHOW_ALL_ITEMS'] === 'T') || ($parameters['SHOW_ALL_ITEMS'] === 'true');
        $iwgroup        = 1;    // one-based
        $poVendor       = array();  // store the virtual PO# per vendor; there will be ONE PO for each vendor
        $poVendorNumber = 1;
        $diagnose       = (($parameters['DIAGNOSE'] ?? false) === true);

        foreach ($itemList as $warehouseID => &$warehouse) {

            foreach ($warehouse as $itemID => &$itemPart) {

                if (isset($this->kitPartInformation[$itemID])) {    // if set, then this is a part of AT LEAST ONE kit (maybe more!)
                    $this->rippleOutKitNeeds($itemID, $warehouseID, $itemPart);
                }

                $itemPart['WAREHOUSE_ITEM_GROUP'] = $iwgroup;   // i.e. all the vendors for this item/warehouse combo get the same number

                $foundOne = false;
                $vendorList = $itemPart['VENDORS'];
                // above here, 'itemPart' is really the entire item+vendors+iwlist structure.
                // to flatten, we have an item-part and a vendor-part that we join into one replenishDetail record.
                unset($itemPart['VENDORS'], $itemPart['IWVLIST']);   // remove all the vendors
                // remove the item warehouse vendor list


                $vendorHasNoTermCannotBeUsedLocalizedStr = null;
                foreach ($vendorList as $vendorID => $vendorPart) {

                    if ($itemPart['REPLENISHMENT_METHOD'] == 'FORECAST_TABLE') {  // this was read from the DB so is in the INTERNAL form
                        $itemPart['FORECAST_TABLE'] = $this->lookUpDemandValue( $itemID, $warehouseID, $vendorPart['LEAD_TIME']);   // so can be different for each vendor
                        $vendorPart['FORECAST_DEMAND_IN_LEAD_TIME'] = $itemPart['FORECAST_TABLE'];    // so the UI doesn't have to pick which field to show
                    }

                    $replenishDetailRec = array_merge( $itemPart, $vendorPart );    // now we have the full record of stuff we fetched and initted
                    $this->replenishDetailMgr->generateCalculatedFields( $replenishDetailRec ); // get computed fields

                    if ($diagnose) {
                        if ($replenishDetailRec['VENDORTERM'] == '') {
                            static $seenVendors = [];
                            if (!isset($seenVendors[$vendorID])) {
                                if (!$vendorHasNoTermCannotBeUsedLocalizedStr) {
                                    $tokens = [
                                        [
                                            'id' => 'IA.VENDOR_HAS_NO_TERM_CANNOT_BE_USED',
                                            'placeHolders' => [
                                                ['name' => 'VENDOR_ID', 'value' => "\'%s\'"]
                                            ]
                                        ]
                                    ];
                                    $text = getLocalizedTextWithThrow($tokens);
                                    $vendorHasNoTermCannotBeUsedLocalizedStr = GT($text, 'IA.VENDOR_HAS_NO_TERM_CANNOT_BE_USED');
                                }
                                $this->diagnostics .= sprintf($vendorHasNoTermCannotBeUsedLocalizedStr, $vendorID);
                                $seenVendors[$vendorID] = true;
                            }
                        }
                        $showAllItems = true;   // so we include stuff otherwise not included
                    }
                    // do we include THIS record in the results?
                    if ($showAllItems || (($replenishDetailRec['QUANTITY_TO_PURCHASE'] > 0) && ($replenishDetailRec['VENDORTERM'] != ''))) {

                        // Each vendor gets exactly ONE PO, regardless of SHIP-TO vs DELIVER-TO
                        if ( ! isset($poVendor[$vendorID])) {
                            $poVendor[$vendorID] = $poVendorNumber; // each vendor gets ONE po
                            $poVendorNumber++;
                        }

                        $replenishDetailRec['PROPOSED_PO']   = $poVendor[$vendorID];
                        $replenishDetailRec['VENDORNAME']    = $replenishDetailRec['VENDORID']   . '--' . $replenishDetailRec['VENDORNAME'];
                        $replenishDetailRec['WAREHOUSENAME'] = $replenishDetailRec['WAREHOUSE'] . '--' . $replenishDetailRec['WAREHOUSENAME'];
                        $replenishDetailRec['WAREHOUSEID']   = $replenishDetailRec['WAREHOUSENAME']; // WAREHOUSEID is the name of the dimension
                        $replenishDetailRec['ITEMNAME']      = $replenishDetailRec['ITEM']       . '--' . $replenishDetailRec['ITEMNAME'];

                        $rtn[] = $replenishDetailRec;

                        $foundOne = true;
                    }
                }

                if ($foundOne) {
                    $iwgroup++;     // item/warehouse combos without a usable vendor shouldn't bump up the number
                } else {
                    unset($itemPart['WAREHOUSE_ITEM_GROUP']);  // so we don't pollute the disk version, if one, with our one-based groups
                }
            }
        }
        return $rtn;
    }



    /**
     *  build Sql Query  Build various parts of the sql query used by clients.  Return a query array filled out.
     *
     *
     * @param array     $parameters          user or API-generated parameters, such as the list of filters
     * @param string    $tableGroup          array of sql tables you want in your query
     * @param string    $additionalSelect    optional fields for the SELECT part of the clause; replaces '{PLACEHOLDER}' in the select list
     *
     * @return string[]                   the generated query
     */
    private function buildSqlQuery($parameters, $tableGroup, $additionalSelect = '')
    {
        $nextParameterNumber    = 2;    // 1 is the CNY# value
        $queryArray             = array( "SELECT \n ", GetMyCompany() );
        $select                 = array();
        $from                   = array();
        $where                  = array();
        $tables                 = $this->tableGroups[ $tableGroup ];

        // 'includeIf' means include this sql table if includeIf === true, OR if 'includeIf is a filter name and we use that filter.
        // example: include the VENDTYPE table if 'VENDOR_TYPE' was specified, so we can find vendors with the filter-specified vendor type
        foreach ($tables as $table => $includeIf) {

            // if true, take the table.  if not true, it is the NAME of a filter, like 'FILTER_VENDOR_TYPE'.
            // See if we have that filter specified, and if so include this table.
            if ($includeIf !== true) {
                if ( ! isset($parameters[$includeIf]) || ($parameters[$includeIf] == '')) {
                    continue;   // we don't have the filter so we don't need this file for this group
                }
            }

            if (!isset($this->sqlTables[$table], $this->joins[$table])) {
                throw new Exception("table not in sqlTables or joins table (code bug!)");
            }

            // shorthand is the short name used in queries, like 'v' for the vendor file
            $shorthand = $this->sqlTables[$table]['FILE_SHORTHAND'];

            // Add to the SELECT list if there is a 'FIELDS' in the file list
            foreach (($this->sqlTables[$table]['FIELDS'] ?? []) as $field) {
                if ($field == "{PLACEHOLDER}") {
                    $field = $additionalSelect;
                }
                $select[] = $field;
            }

            // construct the FROM
            $fileName = ($this->sqlTables[$table]['FILE'] ?? $table); // sometimes there are 'two views' on a file, like ICITEMACTIVITY
            $from[]  = "$fileName $shorthand";

            // construct the WHERE
            foreach ($this->joins[$table] as $join) {
                $where[] = $join;
            }

            // add filters to WHERE as they appear
            foreach ($this->filters as $filter) {
                if (isset($parameters[$filter]) && ($parameters[$filter] != '')) {
                    if (isset($this->sqlTables[$table][$filter])) {
                        $placeholder = '';
                        $haveWhereClause = false;

                        // an array is used for groups, like FILTER_ITEMGROUP
                        if (is_array($parameters[$filter])) {
                            // Hacking note: ALL of my filter values are internally generated as things like itemIDs, warehouseIDs, locationKeys, etc.
                            //      that said, they are all made parameters and are NOT in the inline sql.
                            $operator = '';
                            $placeholder = '';

                            $temp = $queryArray[0]; // we're about to generate a where clause fragment; save the query so far....
                            $queryArray[0] = '';
                            $queryArray = PrepINClauseStmt($queryArray, $parameters[$filter], " $shorthand." . $this->sqlTables[$table][$filter]);
                            $where[] = $queryArray[0]; // save this where clause
                            $queryArray[0] = $temp;    // and put back the query
                            $nextParameterNumber = count($queryArray);
                            $haveWhereClause = true;

                        } else if (is_string($parameters[$filter]) && strpos($parameters[$filter], 'not null') === 0) {
                            $operator = 'is not null';
                        } else if (is_string($parameters[$filter]) && strpos($parameters[$filter], 'is null') === 0) {
                            $operator = 'is null';
                        } else {
                            $operator = '=';
                            $queryArray[$nextParameterNumber] = $parameters[$filter];
                            $placeholder = ":$nextParameterNumber";
                            $nextParameterNumber++;
                        }

                        // special handling for as-of, because we usually compare with <= or >, not =
                        if ($filter == "FILTER_ASOFDATE") {
                            $operator = $this->tableTimePeriod[$tableGroup] ?? self::ON_OR_BEFORE_NOW;
                            $placeholder = "to_date( $placeholder , 'mm/dd/yyyy')"; // and make sure we convert into date format
                        }
                        if ($haveWhereClause === false) {
                            $where[] = $shorthand . '.' . $this->sqlTables[$table][$filter] . " $operator $placeholder";
                        }
                    }
                }
            }
        }

        $groupBy = "";
        if ( isset($this->groupBy[$tableGroup])) {
            $groupBy = " GROUP BY " . $this->groupBy[$tableGroup];
        }

        $orderBy = "";
        if ( isset($this->orderBy[$tableGroup])) {
            $orderBy = " ORDER BY " . $this->orderBy[$tableGroup];
        }

        $queryArray[0] .= implode( ", ", $select) . " FROM " . implode( ", ", $from) . " WHERE " . implode( " AND ", $where) . $groupBy . $orderBy;

        return $queryArray;
    }


    /**
     *  addToLocationList - recursively add locations to the location list; helper for getLocationListForFilter below
     *
     * @param int      $key           the record number of the parent
     * @param array    $locations     the list of location info recs by parent record#
     * @param int[]    $rtn           the resulting list of locations we can use in a query
     */
    private function addToLocationList($key, $locations, &$rtn)
    {
        if (($key > 0) && isset($locations[$key])) { // assign locations with our location as a parent
            foreach ($locations[$key] as $loc) {
                $rtn[] = $loc['RECORD#']; // for a location REF in warehouses we need the record number, not $loc['LOCATION_NO'];
                $this->addToLocationList( $loc['RECORD#'], $locations, $rtn );  // CURSES!  HE RECURSES!
            }
        }
    }


    /**
     *  getLocationListForFilter - given a filter locationkey like 'Intacct', find all locations that match it (like 'Bangalore', 'San Jose', and 'Romania')
     *
     * @param string $locationName     the NAME of the location, like 'Bangalore' or 'Intacct'
     *
     * @return int[]                  the location record#s, suitible for searching in SQL where the 'locationkey' is a record number.
     *                                  If the locationName is empty or non-existant, this returns an empty array
     *
     */
    private function getLocationListForFilter($locationName)
    {
            // This is brute force, I know, but should run fast.
            // How many locations could they have?  A dozen?  A hundred?  A thousand?
        $rtn = array();
        if ($locationName != '') {
            $stmt = array();
            $stmt[0] = "SELECT record#, location_no, parentkey
                        FROM locationmst
                        WHERE cny#=:1 ";
            $stmt[1] = GetMyCompany();
            $res     = QueryResult($stmt);
            if ($res !== false) {
                $locations = array();
                $key = 0;
                foreach ($res as $loc) {
                    if ($loc['LOCATION_NO'] == $locationName) {
                        $key = $loc['RECORD#'];
                        $rtn[] = $key;  // the top-level location
                    }
                    $parent = $loc['PARENTKEY'];    // we want to find kids of our location
                    if ($parent > 0) {              // so if a location has no parents it is of no use to us.
                        $locations[$parent][] = $loc;
                    }
                }
                // So here we ask for the children of the filter location key;
                // this routine will RECURSE and find all the children and add them,
                // then find THEIR children, and so on.
                $this->addToLocationList($key, $locations, $rtn);
            }
        }
        return $rtn;
    }


    /**
     *      get Locatoion Name from record#
     *
     *
     * @param int      $recordNo    the location record number
     *
     * @return string               the fully-qialified name of the location
     */
    private function getLocationNameFromRecordNumber($recordNo)
    {
        if (($recordNo > 0) && ( ! isset($this->locationCache[$recordNo]))) {
            $stmt = array();
            $stmt[0] = "SELECT location_no, name
                        FROM locationmst
                        WHERE cny#=:1 AND record#=:2 ";
            $stmt[1] = GetMyCompany();
            $stmt[2] = $recordNo;
            $res = QueryResult($stmt);
            if (($res !== false) && (count($res) > 0)) {
                $res = $res[0];
                $this->locationCache[$recordNo] = $res['LOCATION_NO'] . '--' . $res['NAME'];
            }
        }
        return ($this->locationCache[$recordNo] ?? '');
    }


    /**
     * @param string[]     $params      customer-supplied parameters such as filters, with possible added group filters
     * @param string       $unitName    the filter for one of these, like FILTER_VENDOR
     * @param string       $groupName   the filter for many of these, like FILTER_VENDOR_GROUP
     * @param string       $entity      the name of the group manager
     */
    private function changeUnitIntoGroup(&$params, $unitName, $groupName, $entity)
    {
        if ($params[ $unitName ] != '') {
            /**
             * @var DimensionGroupManager $groupMgr
             */
            $groupMgr           = Globals::$g->gManagerFactory->getManager($entity);
            $members            = $groupMgr->getGroupMembersById($params[$unitName]);

            if (is_array($members) && (count($members) > 0) && (count($members['MEMBERRECS']) > 0)) {
                unset($params[$unitName]); // not a unit filter, but a unit group
                $params[$groupName] = $members['MEMBERRECS'];
            }
        }
    }


    /**
     * Validate dimension values for the given owned object
     *    This is an override of the base class because it needs to pretend we have a header with a single vendor value
     *    in CUSTVEND, just like POs would have.  That way, the CUSTVEND in the 'header' can be matched against the
     *    vendor in the line's dimension choice.
     *
     *    The code is IDENTICAL to the Entiry Manager code except where noted with comments....
     *
     * @param array  $values          the object values
     * @param string $ownedEntity     the owned entity name
     * @param string $path            the owned object path
     * @param bool   $addErrorDetails true to add error details
     *
     * @return bool      true on success and false on failure
     */
    protected function ValidateDimensionsOnOwnedObject(&$values, $ownedEntity, $path, $addErrorDetails = false)
    {
        if (!is_array($values[$path])) {
            return true;
        }
        $primaryDimensions = $this->getPrimaryDimensions();
        $referentialDimensions = $this->getReferentialDimensions();
        $ok = true;

        if ($addErrorDetails) {
            $invalidRecords = [];
        }
        $lineManager = $this->GetOwnedObjectManager($ownedEntity);
        // handle std dimension fields
        $dimFields = $lineManager->GetDimensionFields();

        // If we do not have any dimensions we just return
        if (!isset($dimFields) || count($dimFields) == 0) {
            return true;
        }
        $dimensionValues = [];

        // this is a cache map for refential dimensions, eg. project to customer
        // it's a multi-level map in the form:
        // dimension => ref dimension => ref value => valid values
        $referenceDimValues = [];

        foreach ($values[$path] as $lineNo => $line) {
            if (array_isnull($line)) {
                continue;
            }
            // **** START OF CHANGE FROM BASE CLASS:
            $values['CUSTVENDID'] = $line['VENDORNAME'];  // make the row's vendor be the 'header' vendor; 'VENDORID' is the selected dimension vendor under scruitiny
            $values['DIMENSION_PATH_TO_USE'] = $path;
            // **** END OF CHANGE FROM BASE CLASS

            foreach ($dimFields as $dimKey => $field) {
                if (!$field['standard']) {
                    continue;
                }
                $fieldid = strtoupper($field['path']);
                if ((!$primaryDimensions[$fieldid] || !$values[$primaryDimensions[$fieldid]])
                    && (!$referentialDimensions[$fieldid] || !$values[$referentialDimensions[$fieldid]])
                    && !isset($field['referentialConstraints'])
                ) {
                    continue;
                }

                $value = $line[$fieldid];
                if (!$value) {
                    continue;
                }

                if ($primaryDimensions[$fieldid] || $referentialDimensions[$fieldid]) {
                    $dimensionValues[$dimKey][] = ['value' => $value, 'line' => $lineNo + 1];
                }

                if (isset($field['referentialConstraints'])) {

                    list($vid) = explode('--', $value);
                    foreach ($field['referentialConstraints'] as $refDim => $refField) {
                        if (!isset($dimFields[$refDim])) {
                            continue;
                        }
                        $refFieldid = strtoupper($dimFields[$refDim]['path']);
                        $refValue = $line[$refFieldid];
                        if (!$refValue) {
                            continue;
                        }

                        list($refVid) = explode('--', $refValue);

                        if (isset($referenceDimValues[$dimKey][$refDim][$refVid])) {
                            $validValues = $referenceDimValues[$dimKey][$refDim][$refVid];
                        } else {
                            $validValues = $this->GetValidValuesForEntity($field['entity'], $dimFields[$refDim]['entity'], $refField, $refVid);
                            $referenceDimValues[$dimKey][$refDim][$refVid] = $validValues;
                        }

                        if (!in_array($vid, $validValues)) {
                            $ok = false;
                            global $gErr;
                            //Adds additional details to error message about the prrecord of the line item
                            if ($addErrorDetails) {
                                /** @noinspection PhpUndefinedVariableInspection */
                                $this->addAdditionalErrorDetails($line, $invalidRecords, $values);
                            }
                            $gErr->addIAError(
                                'INV-0782', GetFL(),
                                "Line " . ($lineNo + 1) . ": The ${field['entity']} you selected is not associated with the $refDim you selected.  When you select a ${field['entity']} dimension, that " . $field['entity'] .
                                " must be associated to the $refDim dimension that you selected at the line level.  (The ${field['entity']} you selected is $value.)  Please go back and select another ${field['entity']}.",
                                ['LINE_NO_PLUS_1' => ($lineNo + 1), 'FIELD_ENTITY' => $field['entity'], 'REF_DIM' => $refDim, 'VALUE' => $value]
                            );
                        }
                    }
                }
            }
        }

        if ($dimensionValues) {
            $ok = $ok && $this->ValidatePrimaryDimensionValues($dimFields, $dimensionValues, $values);
            $ok = $ok && $this->ValidateReferentialDimensionValues($dimFields, $dimensionValues, $values);
        }

        return $ok;
    }



    /**
     * Validate the given dimension values against the primary dimensions
     *    This is an override of the base class because it needs to pretend we have a header with a single vendor value
     *    in CUSTVEND, just like POs would have.  That way, the CUSTVEND in the 'header' can be matched against the
     *    vendor in the line's dimension choice.
     *
     *    The code is IDENTICAL to the Entiry Manager code except where noted with comments....
     *
     * @param array $dimensionFields   the dimension fields metadata
     * @param array $dimensionValues   the dimension values
     * @param array $values            the current object record
     *
     * @return bool     true on success and false on failure
     */
    protected function ValidatePrimaryDimensionValues($dimensionFields, $dimensionValues, $values)
    {
        global $gManagerFactory;
        $ok = true;

        //  Validation function doesn't return read data, no need to track access.
        AdvAuditTracking::setManagedTracking(false);

        $primaryDimensions = $this->getPrimaryDimensions();
        foreach ($dimensionValues as $dimKey => $dimRecords) {
            $dimField = $dimensionFields[$dimKey];
            $dimPath = $dimField['path'];
            if (!isset($primaryDimensions[$dimPath], $values[$primaryDimensions[$dimPath]])) {
                continue;
            }

            // **** START OF CHANGE FROM BASE CLASS:
            $dimMgr = $gManagerFactory->getManager($dimField['type']['entity']);
            if ($dimPath == 'VENDORID') {
                $isVendor = true;
                $children = [];
            } else {
                $isVendor = false;
                list($vidValue) = explode('--', $values[$primaryDimensions[$dimPath]]);
                $children = $dimMgr->getHierarchy($vidValue);
            }
            // **** END OF CHANGE FROM BASE CLASS:

            foreach ($dimRecords as $dimRecord) {

                // **** START OF CHANGE FROM BASE CLASS:
                // Each row's VENDORNAME object should be used instead of the header's 'CUSTVEND' that would be on a PO.
                // ($primaryDimensions[$dimPath] IS CUSTVEND in the vendor case)
                if ($isVendor) {
                    $values[$primaryDimensions[$dimPath]] = $values[$values['DIMENSION_PATH_TO_USE']][$dimRecord['line'] - 1]['VENDORNAME'];   // 'line' is set for the error message, and so is 1-based
                    list($vidValue) = explode('--', $values[$primaryDimensions[$dimPath]]);
                    static $dimCache = [];
                    if ( ! isset($dimCache[$vidValue])) {
                        $dimCache[$vidValue] = $dimMgr->getHierarchy($vidValue);
                    }
                    $children = $dimCache[$vidValue];
                }
                // **** END OF CHANGE FROM BASE CLASS:

                $value = $dimRecord['value'];
                list($vid) = explode('--', $value);
                if (!in_array($vid, $children)) {
                    global $gErr;
                    $fieldInfo = $this->GetFieldInfo($primaryDimensions[$dimPath]);
                    //TODO:i18N-INV-Error-Message: need to get rid of Dictionary usage
                    $dict = Dictionary::getInstance();
                    $renamedDimension = $dict->GetRenamedText($dimField['type']['entity']);
                    $gErr->addIAError(
                        'INV-0853', GetFL(),
                        sprintf('Line %1$s: The %2$s dimension you selected -- %3$s -- is not related to your header-level %4$s dimension.  (The header-level %4$s dimension you selected is %5$s.)  When you select a %2$s dimension, that %2$s must be either the same as or a child of the header-level ${%4$s}.  Please go back and select another %2$s.',
                            $dimRecord['line'], $renamedDimension, $value, $fieldInfo['fullname'], $values[$primaryDimensions[$dimPath]]),
                        [
                            'DIM_RECORD_LINE' => $dimRecord['line'],
                            'DIM_FIELD_TYPE_ENTITY' => $renamedDimension,
                            'VALUE' => $value,
                            'FULLNAME' => $fieldInfo['fullname'],
                            'PRIMARY_DIMENSIONS_DIM_PATH' => $values[$primaryDimensions[$dimPath]]
                        ]
                    );
                    $ok = false;
                }
            }
        }
        return $ok;
    }


    /**
     *      Given a department name, return the department recod number.
     *      No name or missing name returns zero.
     *
     * @param string $departmentName
     *
     * @return int
     */
    private function getDepartmentRecordNumFromDepartment($departmentName)
    {
        $rtn = 0;
        if (!empty($departmentName)) {
            list($department) = explode('--', $departmentName);

            static $departmentCache = [];   // I'd expect many rows to have the same department
            if ( ! isset($departmentCache[$department])) {
                /** @var DepartmentManager $departmentManager */
                $departmentManager = Globals::$g->gManagerFactory->getManager('department');
                $row = $departmentManager->Get($department,["RECORDNO"]); // although, currently, the department manager does not honor the list of fields
                if ($row !== false) {
                    $departmentCache[$department] = (int)$row["RECORDNO"];
                }
            }
            $rtn = $departmentCache[$department] ?? 0;      // in case of failure above or no dept found
        }
        return $rtn;
    }


    /**
     * validateAndCleanupValues - Validate the parameters given to the API
     *
     * @param string $whatAreWeDoing    constants that may cause us to do additional tests.  Are we fetching data/a snapshot, or are we generating POs?
     * @param array $params             from the user or API, such as filters, the as-of date, and so on
     *
     * @return bool
     */
    private function validateAndCleanupValues($whatAreWeDoing, &$params)
    {
        $ok = true;

        // Is replenishment on?
        global $gMultipleVendorsPrefIValues, $gMultipleVendorsPrefValues;

        // We could do this in the constructor, but I'm not sure the transaction definition is always set up by then, or if it could change between there and here....
        // Note: the UI has the field DELIVERTOHEADER, which is initialized to contain the default deliver-to header.  The customer can change that, and we'll use it.
        //      the customer can also make it empty, which is fine; we'll pretend DELIVER-TO is off.
        $this->podocumentMgr        = Globals::$g->gManagerFactory->getManager('podocument', true, ['DOCTYPE' => $params['TRANSACTION_DEFINITION']] );
        $isVatEnabled               = $this->podocumentMgr->isVATEnabled();
        $this->deliverToHeader      = ($this->podocumentMgr->isDeliverToHeaderItemEnable() || $isVatEnabled) ? $params['DELIVERTOHEADER'] : ''; // $this->podocumentMgr->deliverToHeaderDefault();
        $this->deliverToLine        = ($this->deliverToHeader != '') && ($this->podocumentMgr->isShipToLineItemEnable() || $isVatEnabled);

        $replenishment = (($this->inventoryPrefs['AI_REPLENISHMENTS'] == 'T') && ($this->inventoryPrefs['ADVANCED_INVENTORY'] == 'T'));
        if ( ! $replenishment) {
            Globals::$g->gErr->addIAError('INV-0243', __FILE__ . ':' . __LINE__,
                "To use replenishment, enable replenishment on the Configure Inventory Control page.",[] );
            return false;
        }

        $dimensionsEnabled = IADimensions::getModuleDimensions('gl'); // use the GL preferences to find the enabled dimensions
        if (isset($dimensionsEnabled) && is_array($dimensionsEnabled)) {
            if (!isset($dimensionsEnabled['item'], $dimensionsEnabled['warehouse'], $dimensionsEnabled['vendor'])) {
                Globals::$g->gErr->addIAError('INV-0244', __FILE__ . ':' . __LINE__,
                    "To use replenishment, ensure that the Item, Vendor, and Warehouse dimensions are all
                    enabled in the General Ledger (Dimension settings section in the General Ledger
                    Setup page).",[] );
                return false;
            }
        }

        if (($params['FILTER_LOCATIONKEY'] == '') && IsMultiEntityCompany() && GetContextLocation()) {
             $params['FILTER_LOCATIONKEY'] = GetContextLocation(true);  // true returns the location short name
        }

        if ($params['FILTER_LOCATIONKEY'] != '') {

            // DANGER!! NOTE!!
            //      This turns the location into an array of RECORD NUMBERS of the location + all children.
            //  If you are comparing locationkeys in most records, it is the location NAME, not the record number.
            //  But I'm dealing with the RECORD# in the warehouse 'locationKeyRef' field.
            $params['FILTER_LOCATIONKEY'] = $this->getLocationListForFilter( $params['FILTER_LOCATIONKEY'] );   // expand this
            if (count($params['FILTER_LOCATIONKEY']) == 0) {
                Globals::$g->gErr->addIAError('INV-0245', __FILE__ . ':' . __LINE__,
                    "Specify a location that exists.",[] );
                return false;
            }
        }

        // Required fields:  AsOfDate (Warehouse was required in the original spec, but I hear now it is not required)
        if ($whatAreWeDoing == self::GENERATE_SNAPSHOT) {

            // default snapshot name to 'current'
            if (! isset($params['SNAPSHOT_NAME'])) {
                $tokens = [
                    [
                        'id' => 'IA.DEFAULT_SNAPSHOT_NAME',
                        'placeHolders' => [
                            ['name' => 'DATE', 'value' => GetCurrentDate()]
                        ]
                    ]
                ];
                $text = getLocalizedTextWithThrow($tokens);
                $params['SNAPSHOT_NAME'] = GT($text, 'IA.DEFAULT_SNAPSHOT_NAME');
            }

            if (!isset($params['FILTER_ASOFDATE'])) {
                Globals::$g->gErr->addIAError('INV-0246', __FILE__ . ':' . __LINE__,
                    "Specify a value for 'As of date', and try again.",[]);
                return false;
            }

            if (!isset($params['TRANSACTION_DATE'])) {
                $params['TRANSACTION_DATE'] = $params["FILTER_ASOFDATE"];
            }

            $vendorSort     = $params['SHOW_VENDOR_OPTION'];
            if ($vendorSort == '') {
                $vendorSort  = 'PREF_VENDOR';   // see $gMultipleVendorsPrefIValues for these values
            } else {
                foreach ($gMultipleVendorsPrefValues as $key => $vendorOption) {
                    if ($vendorSort == $vendorOption) {
                        $vendorSort = $gMultipleVendorsPrefIValues[$key];   // translate into internal form
                    }
                }
            }
            $params['SHOW_VENDOR_OPTION_INTERNAL'] = $vendorSort;   // less embeded English

            // is the item filter really an item group?  And the others
            $this->changeUnitIntoGroup( $params, 'FILTER_ITEM',        'FILTER_ITEMGROUP',        'itemgroup' );
            $this->changeUnitIntoGroup( $params, 'FILTER_VENDORID',    'FILTER_VENDORGROUP',      'vendorgroup' );
            $this->changeUnitIntoGroup( $params, 'FILTER_WAREHOUSE',   'FILTER_WAREHOUSEGROUP',   'warehousegroup' );

            // *** SUPPLIES INVENTORY ***
            // is this a Supplies Inventory run where we get a list of docentry records to replenish?
            $isSupplies  = (($params['is_supplies'] ?? 'false') === 'true');
            if ($isSupplies && (($params['docEntryRecords'] ?? '') != '')) {
                $recordArray     = explode(',', $params['docEntryRecords']);
                $docEntryManager = Globals::$g->gManagerFactory->getManager('documententry');
                $list            = $docEntryManager->GetList([
                    'selects'       => ['ITEMID', 'WAREHOUSE.LOCATION_NO', 'WAREHOUSE.RECORDNO', 'ITEM.RECORDNO'],
                    'filters'       => [[['RECORDNO', 'in', $recordArray]]],
                    'usemst'        => true
                ]);
                if ($list === false) {
                    return false;
                }
                // now pretend that the warehouses are part of a warehouse group, and items part of an item group
                $warehouses = [];
                $items     = [];
                foreach ($list as $row) {
                    $warehouses[ $row['WAREHOUSE.RECORDNO'] ] = true; // avoid dups
                    $items[      $row['ITEM.RECORDNO']      ] = true;
                }
                $params['FILTER_WAREHOUSEGROUP'] = array_keys($warehouses);
                $params['FILTER_ITEMGROUP']      = array_keys($items);

                // folks asked for item X and they expect to see it, even if it is not needed.
                // "why are these empty?"
                $params['SHOW_ALL_ITEMS']        = 'true';
            }
        }

        if ($whatAreWeDoing == self::GENERATE_POS) {

            // default transaction date to as-of date
            if (!isset($params['TRANSACTION_DATE'])) {
                $params['TRANSACTION_DATE'] = $params["FILTER_ASOFDATE"];
                if ($params['TRANSACTION_DATE'] == '') {
                    Globals::$g->gErr->addIAError('INV-0247', __FILE__ . ':' . __LINE__,
                        "Specify both a ‘Purchasing transaction date’ and an ‘As of date’. Then, try again.",
                        []);
                    $ok = false;
                }
            }

            if ($params['EXECUTOION_MODE'] == 'Offline') {
                $contactInfo = GetMyContact();
                if (($contactInfo === false) || ($contactInfo['EMAIL1'] == '') || $contactInfo['FIRSTNAME'] == '') {
                    Globals::$g->gErr->addIAError('INV-0248', __FILE__ . ':' . __LINE__,
                        "Update your email address in your user preferences so we can contact you after
                        the purchase orders are created.",[]);
                    $ok = false;
                }
            }
            if ( ! $this->ValidateRecord($params)) {
                $ok = false;
            }
        }

        // need this in either case....
        if (! isset($params['TRANSACTION_DEFINITION'])) {
            Globals::$g->gErr->addIAError('INV-0249', __FILE__ . ':' . __LINE__,
                "Select a transaction definition that has an associated price list, which we need to
                provide accurate pricing and generate the purchase orders. Then, try again.",[]);
            $ok = false;
        }

        $poDocumentParamsManager    = Globals::$g->gManagerFactory->getManager('podocumentparams');
        $this->docpar               = $poDocumentParamsManager->GetLatestRaw( $params['TRANSACTION_DEFINITION']);
        if (($this->docpar === false) || ( ! isset($this->docpar[0]))) {
            Globals::$g->gErr->addIAError('INV-0250', __FILE__ . ':' . __LINE__,
                "Specify a valid transaction definition that is active.", []);
            $ok = false;
        }
        $this->docpar = $this->docpar[0];

        $this->currencyExchangeID   = INTACCT_RATE_ID;
        $this->currencyExchangeName = INTACCT_RATE;
        if (($this->docpar['OVERRIDE_EXCH_RATE_TYPE'] == 'T') && ($this->docpar['EXCH_RATE_TYPE_ID'] > 0)) {
            $this->currencyExchangeID   = $this->docpar['EXCH_RATE_TYPE_ID'];
            $exchangeRateTypesManager   = Globals::$g->gManagerFactory->getManager('exchangeratetypes');
            $this->currencyExchangeName = $exchangeRateTypesManager->GetExchangeRateTypeName($this->currencyExchangeID);
        }

        if (!$this->isDocTypeAllowed($params['TRANSACTION_DEFINITION'], "create")) {
            $ok = false;
        }

        // It cannot affect on hand or on hold....
        $query = "SELECT 1 
                FROM docpartotals, ictotal 
                WHERE docpartotals.docparkey = :1 and 
                      ictotal.record# = docpartotals.totalkey and 
                      (ictotal.name = 'ONHAND' OR ictotal.name = 'ONHOLD') and
                      ictotal.cny#      = :2  and 
                      docpartotals.cny# = :2 ";
        // do I also want "docpartotals.q_qv in ('V','QV') and"?

        $cny = GetMyCompany();
        $res = QueryResult(array($query, $this->docpar['RECORD#'], $cny));
        if (($res !== false) && is_array($res) && (count($res) > 0)) {
            Globals::$g->gErr->addIAError('INV-0251', __FILE__ . ':' . __LINE__,
                "Select a transaction definition that does not affect ONHAND or ONHOLD.", []);
            $ok = false;
        }


        // we store the department record # on disk, so get it from the name.
        if(isset($params['ITEMS_ORDERING_INFO']) && !empty($params['ITEMS_ORDERING_INFO'])) {
            foreach ($params['ITEMS_ORDERING_INFO'] as &$row) {
                unset($row["DEPARTMENTDIMKEY"]);
                if (isset($row['DEPARTMENT'])) {
                    $row["DEPARTMENTDIMKEY"] = $this->getDepartmentRecordNumFromDepartment($row['DEPARTMENT']);
                }
            }
        }

        return $ok;
    }


    /**
     *      save Snapshot - given snapshot data, save it!  (This is part of this manager's add() functionality
     *
     * @param array $values
     * @param array $snapshotData
     *
     * @return bool
     */
    function saveSnapshot(&$values, &$snapshotData)
    {
        // save the filters since we change them:
        $this->pushFilters($values);
        foreach ($this->filters as $saveFilter) {
            if (isset($values[$saveFilter]) && is_string($values[$saveFilter]) && (strpos($values[$saveFilter],'--') !== false)) {
                list($values[$saveFilter]) = explode('--', $values[$saveFilter]);   // remove the -- between the id and the name, if one
            }
        }

        // Make sure replenishment is on and this customer is valid to use it
        // Make sure needed fields are present in $values
        // Note: we did this before in 'generate snapshot' perhaps,
        //      but because we push/pop the filter values, we need the
        //      fixed values for saving....
        $ok = $this->validateAndCleanupValues( self::GENERATE_SNAPSHOT, $values );
        if ($ok) {
            $source = __METHOD__;
            $this->_QM->beginTrx($source);

            // Set when created/who did it
            $currentTime = GetTimestampGMT();
            $userID = GetMyUserid();

            if (!isset($values['WHENCREATED'])) {
                $values['WHENCREATED'] = $currentTime;
                $values['CREATEDBY'] = $userID;
            }
            $values['WHENMODIFIED'] = $currentTime;
            $values['MODIFIEDBY'] = $userID;
            $values['SNAPSHOT_CREATED'] = (isset($snapshotData[0]) ? 'true' : 'false'); // note that the Entity Manager will convert these to T/F

            // remove any old snapshot by name;  The UI should notify folks that we're doing this if that is a concern
            $ok = ExecStmt(array("DELETE replenishment WHERE cny# = :1 and SNAPSHOT_NAME = :2",   // we're a new record, so delete any records with our name
                GetMyCompany(),
                $values['SNAPSHOT_NAME']));

            $ok = $ok && ExecStmt(array("DELETE replenishdetail WHERE cny#= :1 and SNAPSHOT_NAME = :2",    // detail record
                GetMyCompany(),
                $values['SNAPSHOT_NAME']));

            foreach ($snapshotData as $key => $replenishDetailRecord) {
                unset($values['ITEMS_ORDERING_INFO'][$key]['SUMMARY_RECORDNO'], $values['ITEMS_ORDERING_INFO'][$key]['RECORDNO']);
                $values['ITEMS_ORDERING_INFO'][$key]['SNAPSHOT_NAME'] = $values['SNAPSHOT_NAME']; // in case it has changed
            }
            // always add.  This way, the same set of data can be under two snapshot names.
            // if it is re-saving under the SAME name, we just deleted the record above
            unset($values['RECORDNO']);
            $this->setBypassHandleCustomRelationships(true);
            $ok = $ok && parent::regularAdd($values);  // This writes everyting to disk

            if ($ok) {
                $ok = $this->_QM->commitTrx($source);
            } else {
                $this->_QM->rollbackTrx($source);
            }
            $this->setBypassHandleCustomRelationships(false);
        }

        // put the filter values back
        $this->popFilters($values);

        return $ok;
    }






    //  *******************************************************************************************************************
    //  *******************************************************************************************************************
    //
    //      Add / Create        (Entity Manager function is 'add'(), but the XML op is 'Create')
    //
    //  *******************************************************************************************************************
    //  *******************************************************************************************************************

    /* *********************
            XML API:

        Add/create a new snapshot

        <content>
          <function controlid="testFunctionId">
            <create>
              <REPLENISHMENT>
                <FILTER_ASOFDATE>01/30/2018</FILTER_ASOFDATE>
                <SHOW_ALL_ITEMS>true</SHOW_ALL_ITEMS>
              </REPLENISHMENT>
            </create>
          </function>
        </content>


       ************************
       */

    /**
     * Add new snapshot object override
     *
     * @param array     &$values    Class object details in the form of array
     *
     * @return bool True|False based on Success or Failure of the method call
     */
    protected function regularAdd(&$values)
    {
        $ok = $this->generateSnapshot( $values, $snapshotData );
        if ($ok) {
            $ok = $this->saveSnapshot( $values, $snapshotData );
        }

        return $ok;
    }




    //  ****************************************************************************************
    //  ****************************************************************************************
    //
    //      GENERATE PO's
    //
    //  ****************************************************************************************
    //  ****************************************************************************************




    /**
     * Kick off an asynchronous request to create the POs
     *
     *  DEVELOPERS: In Production, there is a cron job that runs these offline tasks.
     *      But in dev, you must go into the browser and do something like this (replace your sandbox and company title as needed):
     *
     *  https://dev09.intacct.com/users/rcollins/svn.advancedinventory/tools/imsq_cron.phtml?.context=RSC-SRP
     *
     * @param string[] $values
     *
     * @return bool
     */
    function generatePOsOffline($values)
    {
        // so we don't loop around and generate offline forever
        unset($values['OFFLINE'], $values['SNAPSHOT'], $values['std_buttons'], $values['DYNAMIC_HELP_INFORMATION']);
        $values['EXECUTOION_MODE'] = 'Offline';

        // We'll do this again, but do it now in case there are errors.....
        $valuesTemp = $values;
        if ( ! $this->validateForPOs($valuesTemp, $pos )) {
            return false;
        }

        // placeholder so folks know it is in the queue to run
        $replenishmentRun = array(
            'RECORDNO' => 0,
            'RUN_DATE' => GetCurrentDate(),
            'RUN_BY' => GetMyLogin(),
            'TRANSACTION_DEFINITION' => $values['TRANSACTION_DEFINITION'],
            'TRANSACTION_DATE' => $values['TRANSACTION_DATE'],
            'STATE' => 'In Queue',
            'EXECUTOION_MODE' => $values['EXECUTOION_MODE'],
            'TRANSACTION_COUNT' => 0,
            'ITEM_COUNT' => 0,
            'PURCHASE_AMOUNT_BASE' => 0,
            'WHENCREATED' => GetTimestampGMT(),
            'WHENMODIFIED' => GetTimestampGMT(),
            'CREATEDBY' => GetMyUserid(),
            'MODIFIEDBY' => GetMyUserid(),

            'REPLENISHRUN_DETAIL' => array(),
        );

        foreach ($pos as $POLines) {
            $replenishmentRun['TRANSACTION_COUNT']++;
            $replenishmentRun['ITEM_COUNT'] += count($POLines);
        }

        $rrMgr = Globals::$g->gManagerFactory->getManager('replenishmentrun');
        $rrMgr->add( $replenishmentRun );
        $values['RECORDNO']                 = $replenishmentRun['RECORDNO'];
        $values['REPLENISHMENT_RUN_RECORD'] = $replenishmentRun;    // save for the actual run

        $pub = new ims_publish_1( IMS_MODE_NONBLOCKING , IMS_PROCESS_REMOTE , IMS_MODE_QUEUED);

        $msgBody = array(
            'params' => $values,
            'action' => 'createposoffline' );

        $ok = $pub->PublishMsg(
            'CREATEPOSOFFLINE',
            'INTACCT',
            'RUN_OFFLINEACTION',
            IMS_PRIORITY_DEFAULT,
            $msgBody,
            '',
            $response
        );

        return $ok;
    }




    /**
     *      generate POs - given the array of item/warehouse/vendors, generate those that are checked.
     *
     * @param array $values
     * @param array $replenishmentRun
     *
     * @return bool
     */
    function generatePOs(&$values, &$replenishmentRun)
    {
        // save the filters since we change them:
        $this->pushFilters($values);
        foreach ($this->filters as $filterName) {
            if (isset($values[$filterName]) && is_string($values[$filterName]) && (strpos($values[$filterName],'--') !== false)) {
                list($values[$filterName]) = explode('--', $values[$filterName]);   // remove the -- between the id and the name, if one
            }
        }

        $replenishmentRun = array();
        $this->setDocType($values['TRANSACTION_DEFINITION']);   // this is needed to populate custom dimensions and other such things

        if (($values['OFFLINE'] === 'true') || ($values['OFFLINE'] === 'T')) {  // here if we came from the API, perhaps
            return $this->generatePOsOffline( $values );
        }

        if (isset($values['SNAPSHOT'])) {   // from the API, a less weird name
            $values['ITEMS_ORDERING_INFO'] = $values['SNAPSHOT'];
            unset($values['SNAPSHOT']);
        }

        $source = "ReplenishmentManager:generatePOs";
        $managerFactory = Globals::$g->gManagerFactory;
        $values['RECORDNO'] = 0;

        $ok = $this->validateForPOs($values, $POs );

        if ($ok) {        // Stuff needed for each PO, so get it once:

            $errorCheckpoint        = Globals::$g->gErr->Checkpoint();

            $IsDocParApprovalEnabled = $this->podocumentMgr->IsDocParApprovalEnabled($values['TRANSACTION_DEFINITION']);
            if ($IsDocParApprovalEnabled) {
                $state = DocumentManager::SUBMITTED_STATE;
            } else {
                $convMgr        = new ConversionManager(array('mod' => 'po')); // why 'new'?  Dunno, but this is what PODocumentManager does....
                $canConvertTo   = $convMgr->GetAllowedDocsToConvertFrom($values['TRANSACTION_DEFINITION']);

                if (count($canConvertTo) > 0) {
                    $state = DocumentManager::PENDING_STATE;
                } else {
                    $state = DocumentManager::CLOSED_STATE; // cannot convert to anything, so it is closed
                }
            }

            $rrMgr = $managerFactory->getManager('replenishmentrun');

            // If we were offline, there is a Replenishment Run record sitting in 'values'.
            // Otherwise we should create one from scratch
            if (isset($values['REPLENISHMENT_RUN_RECORD'])) {
                $replenishmentRun = $values['REPLENISHMENT_RUN_RECORD'];
                $replenishmentRun['ITEM_COUNT'] = 0;            // these will be filled in below
                $replenishmentRun['TRANSACTION_COUNT'] = 0;
                $replenishmentRun['WHENMODIFIED'] = GetTimestampGMT();
                $replenishmentRun['STATE'] = 'Success';
                unset($values['REPLENISHMENT_RUN_RECORD']);
            } else {
                $replenishmentRun = array(
                    'RUN_DATE'               => GetCurrentDate(),
                    'RUN_BY'                 => GetMyLogin(),
                    'TRANSACTION_DEFINITION' => $values['TRANSACTION_DEFINITION'],
                    'TRANSACTION_DATE'       => $values['TRANSACTION_DATE'],
                    'STATE'                  => 'Success',
                    'EXECUTOION_MODE'         => ($values['EXECUTOION_MODE'] ?? 'Online'),
                    'TRANSACTION_COUNT'      => 0,
                    'ITEM_COUNT'             => 0,
                    'PURCHASE_AMOUNT_BASE'   => 0,
                    'WHENCREATED'            => GetTimestampGMT(),
                    'WHENMODIFIED'           => GetTimestampGMT(),
                    'CREATEDBY'              => GetMyUserid(),
                    'MODIFIEDBY'             => GetMyUserid(),

                    'REPLENISHRUN_DETAIL'    => array(),
                );
            }

            $this->_QM->beginTrx($source);

            $oneCreatedOk = false;
            $oneErroredOut = false;

            // Now back to creating PO's
            foreach ($POs as $POLines) {

                $okCreate = $this->CreatePOTransaction($values, $lastPO, $values['ITEMS_ORDERING_INFO'], $POLines, $state );

                $firstRow  = $values['ITEMS_ORDERING_INFO'][$POLines[0]];
                $lastPOLine0 = $lastPO['ENTRIES'][0];
                $replenishRunDetail = array(
                    'VENDORNAME' => $lastPOLine0['VENDORNAME'],
                    'TRANSACTION_ID' => ($lastPOLine0['DOCHDRID'] ?: $lastPOLine0['DOCNO']),
                    'NUMBER_OF_ITEMS' => count($POLines),
                    'TRANSACTION_AMOUNT' => 0.0,
                    'TRANSACTION_AMOUNT_BASE' => 0,
                    'CURRENCY' => $firstRow['CURRENCY'],
                    'STATE' => (isset( $firstRow['CURRENCY_WARNINGS']) ? 'Warnings' : 'Created'),
                    'ERROR_MESSAGE' => $firstRow['CURRENCY_WARNINGS'] ?? '',
                );

                $txnAmount = 0.0;
                $txnAmountBase = 0.0;

                if ($okCreate) {
                    $oneCreatedOk = true;
                    // we changed something.  Commit it in case the next go-around causes errors.
                    // then start a new transaction for the next pass
                    $this->_QM->commitTrx($source);
                    $replenishmentRun['TRANSACTION_COUNT'] ++;
                    $replenishmentRun['ITEM_COUNT']        += count($POLines);
                    foreach ($lastPO['ENTRIES'] as $entry) {
                        $exchRate       = $entry['EXCHRATE'];
                        $lineAmount     = $entry['TRX_ENDVALUE'];
                        $txnAmount     += $lineAmount;
                        $txnAmountBase += ($lineAmount * $exchRate);    // or do we divide?
                    }
                } else {
                    $oneErroredOut = true;
                    //  Get ALL the errors for this PO and reset the error stack so we can keep going.
                    $poMessages = Globals::$g->gErr->errorStringsWithCorrections(true, 20);
                    $poMessages = str_replace( "\n", "; ", $poMessages);

                    if (strlen($poMessages) >= self::MAX_ERROR_LENGTH) {
                        $poMessages = substr($poMessages, 0, self::MAX_ERROR_LENGTH - 4) . '...';
                    }

                    $replenishRunDetail['STATE'] = 'Failed';
                    $replenishRunDetail['ERROR_MESSAGE'] .= $poMessages;

                    Globals::$g->gErr->Restore($errorCheckpoint);   // reset the error table back to what it was before we called this.
                    $this->_QM->rollbackTrx($source);               // roll back this one
                }
                $replenishRunDetail['TRANSACTION_AMOUNT'] = $txnAmount;
                $replenishRunDetail['TRANSACTION_AMOUNT_BASE'] = $txnAmountBase;
                $replenishmentRun['REPLENISHRUN_DETAIL'][] = $replenishRunDetail;
                $replenishmentRun['PURCHASE_AMOUNT_BASE'] += $txnAmountBase;

                $this->_QM->beginTrx($source);                     // and start a new one for next time
            }

            if ($ok) {
                $replenishmentRun['STATE'] = 'Success';
                if ($oneErroredOut) {
                    if ($oneCreatedOk) {
                        $replenishmentRun['STATE'] = 'Partial Success';
                    } else {
                        $replenishmentRun['STATE'] = 'Failed';
                    }
                }
                if ( ! isset($replenishmentRun['RECORDNO'])) {
                    $ok = $rrMgr->add($replenishmentRun);
                } else {
                    $ok = $rrMgr->set($replenishmentRun);
                }
                $recordNo = $replenishmentRun['RECORDNO'];
                $values['RECORDNO'] = $recordNo;
            }
            if ($ok) {
                $ok = $this->_QM->commitTrx($source);
            } else {
                $this->_QM->rollbackTrx($source);
            }
        }

        // put the filter values back
        // put the filter values back
        $this->popFilters($values);

        if ($values['EXECUTOION_MODE'] == 'Offline') {
            $this->sendEmail( $replenishmentRun );
        }

        return $ok;
    }


    /**
     *      send Email - in offline mode, when creating POs is done, send an email to the user
     *
     * @param array $replenishmentRun
     *
     */
    private function sendEmail($replenishmentRun)
    {
        $contactInfo = GetMyContact();
        $emailId   = $contactInfo['EMAIL1'];
        $firstName = $contactInfo['FIRSTNAME'];
        $succeeded = 0;
        $failed    = 0;
        $firstDoc  = "";
        $lastDoc   = "";

        $recordNumber = $replenishmentRun['RECORDNO'];

        foreach ($replenishmentRun['REPLENISHRUN_DETAIL'] as $replenishRunDetail) {
            if ($replenishRunDetail['STATE'] == 'Failed') {
                $failed++;
            } else {
                $succeeded++;
                if ($firstDoc == "") {
                    $firstDoc = $replenishRunDetail['TRANSACTION_ID'];
                }
                $lastDoc = $replenishRunDetail['TRANSACTION_ID'];
            }
        }

        //EMAIL SUBJECT
        $companyTitle = GetMyCompanyTitle();
        $tokens = [
            [
                'id' => 'IA.REPLENISHMENT_EMAIL_SUBJECT',
                'placeHolders' => [
                    ['name' => 'COMPANY_TITLE', 'value' => $companyTitle]
                ]
            ]
        ];
        $text = getLocalizedTextWithThrow($tokens);
        $subjectPhrase = GT($text, 'IA.REPLENISHMENT_EMAIL_SUBJECT');

        //EMAIL SEE RESULT
        if ($failed > 0) {
            // ...some transactions weren’t created because ...
            $tokens = [
                [
                    'id' => 'IA.REPLENISHMENT_EMAIL_SEE_RESULT_WITH_ERRORS',
                    'placeHolders' => [
                        ['name' => 'COMPANY_TITLE', 'value' => $companyTitle],
                        ['name' => 'RECORDNO', 'value' => $recordNumber]
                    ]
                ]
            ];
            $text = getLocalizedTextWithThrow($tokens);
            $seeResults = GT($text, 'IA.REPLENISHMENT_EMAIL_SEE_RESULT_WITH_ERRORS');
        } else {
            $tokens = [
                [
                    'id' => 'IA.REPLENISHMENT_EMAIL_SEE_RESULT',
                    'placeHolders' => [
                        ['name' => 'COMPANY_TITLE', 'value' => $companyTitle],
                        ['name' => 'RECORDNO', 'value' => $recordNumber]
                    ]
                ]
            ];
            $text = getLocalizedTextWithThrow($tokens);
            $seeResults = GT($text, 'IA.REPLENISHMENT_EMAIL_SEE_RESULT');
        }

        //EMAIL BODY
        $tokens = [
            [
                'id' => 'IA.REPLENISHMENT_EMAIL_BODY',
                'placeHolders' => [
                    ['name' => 'FIRST_NAME', 'value' => $firstName],
                    ['name' => 'COMPANY_TITLE', 'value' => $companyTitle],
                    ['name' => 'DATE_TIME', 'value' => date('m/d/Y g:i:s A', time())],
                    ['name' => 'RECORDNO', 'value' => $recordNumber],
                    ['name' => 'FAILED_ERRORS', 'value' => $failed],
                    ['name' => 'SUCCEED_TRANSACTIONS', 'value' => $succeeded],
                    ['name' => 'FIRST_DOC', 'value' => $firstDoc],
                    ['name' => 'LAST_DOC', 'value' => $lastDoc]
                ]
            ]
        ];
        $text = getLocalizedTextWithThrow($tokens);
        $body = GT($text, 'IA.REPLENISHMENT_EMAIL_BODY');
        $body .= $seeResults . "\n\n" . 'IA.REPLENISHMENT_EMAIL_SALUTATION';

        $emailArray = preg_split("/\s*,\s*/", $emailId);
        foreach ($emailArray as $address) {
            EmailHelper::ia_mail(
                $address,
                $subjectPhrase,
                $body,
                'IA.REPLENISHMENT_EMAIL_HEADER');
        }

    }


    //  ********************************************************
    //  ********************************************************
    //
    //      NOTE: COPIED ROUTINES
    //
    //  These next few routines are largely COPIES
    //  of the same routines in xmlgw_router.2.1.cls.
    //
    //  I like the documentation for the XML API, but there is
    //  no 'back door' to call into it part way through processing.
    //  James McGonegal suggested copying routines, as they take
    //  the DOCUMENTED API and converts it to podocumentManager::regularAdd()
    //  format
    //
    //  ********************************************************
    //  ********************************************************




    /**
     * Check if the Document is allowed to create.
     * This function checks for the Doctype existence ,whether a document is active or
     * inactive and if user is having permission to create a transaction
     *
     * @param string $transactionType
     * @param string $opType
     *
     * @return bool
     */
    function isDocTypeAllowed($transactionType, $opType)
    {
        $isTransTypeActive = (strtoupper($this->docpar['STATUS']) == 'T');
        if (!$isTransTypeActive) {
            Globals::$g->gErr->addIAError(
                'INV-0783', __FILE__ . ":" . __LINE__,
                "The status of transaction definition " . $transactionType . " is inactive.  Specify a transaction definition that is active.",
                ['TRANSACTION_TYPE' => $transactionType]
            );
            return false;

        } else {
            if (strtoupper($this->docpar['USERPERM']) == 'T') {
                global $MODNAME, $POLNAME, $_userid;
                $userIDAsArray = explode('@', $_userid);
                $userkey = array_shift($userIDAsArray);
                $fs = new FSEntityManager();
                if (!$fs->IsPathAllowedForUser($transactionType, $userkey, $MODNAME, $POLNAME)) {
                    Globals::$g->gErr->addIAError(
                        'INV-0784', __FILE__ . ":" . __LINE__,
                        "You do not have permission to create or update " . $transactionType . " transactions.",
                        ['TRANSACTION_TYPE' => $transactionType]
                    );
                    return false;
                }
            }

            if ($opType == "edit") {
                if ($this->docpar['EDITTYPE'] == 'N') {
                    Globals::$g->gErr->addIAError(
                        'INV-0785', __FILE__ . ":" . __LINE__,
                        "The transaction definition " . $transactionType . " has a non-editable edit policy. Specify a transaction definition that can be edited.",
                        ['TRANSACTION_TYPE' => $transactionType]
                    );
                    return false;
                }
            }
        }

        return $this->ValidateVendorDocNumber($this->docpar); // see if we need a vendor doc number; I don't currently have it.  :-(
    }


    /**
     * ValidateVendorDocNumber - copied from PODocumentManager.cls
     *
     * @param array $docpar
     *
     * @return bool
     */
    function ValidateVendorDocNumber($docpar)
    {
        $ok = true;
        global $kAPid;

        $billNoPref = GetPreferenceForProperty($kAPid, 'BILLNOREQUIRED');
        $billnorequired = ($billNoPref
            && $docpar['SALE_PUR_TRANS'] == 'Purchase'
            && $docpar['UPDATES_GL'] == 'A');

        if ($billnorequired) {    // we don't have this per vendor
            Globals::$g->gErr->addIAError('INV-0252', __FILE__ . ":" . __LINE__,
                "Your Accounts Payable configuration requires the ‘Vendor document number field’, "
                            . "which the replenishment process cannot supply.  Change the setting by deselecting 'Bills, adjustments, "
                            . "quick bill entry and recurring bills only' in the ‘Document Sequencing' section on the Configure Accounts Payable page.",[]);
            $ok = false;
        }
        return $ok;
    }



    //  ********************************************************
    //  ********************************************************
    //
    //   Create ONE PO
    //
    //  ********************************************************
    //  ********************************************************


    /**
     *  Find any custom dimensions and copy them to the destination if they are present
     *
     * @param string[] $src     One Replenish Detail record
     * @param string[] $dest    One line itenm for the PO
     */
    private function CopyCustomDimensions($src, &$dest)
    {
        if (!util_isPlatformDisabled()) {

            $custdimFieldsMap = GLEntryManager::getPTFieldsMap();
            $fieldNames = array_values($custdimFieldsMap);

            foreach ($fieldNames as $fname) {
                if (isset($src[$fname])) {
                    $dest[$fname] = $src[$fname];
                }
            }
        }
    }


    /**
     *  Copy the standard dimensionsk if present, from the parameters sent to us by the UI into the destination
     *
     *      Now, there's a bit of a challenge here; the dimensions are in NAME format but I want them in RECORD-NUMBER format.
     *      So, do a reverse lookup.  Sonmehow document forms manage to do this for free, but Khiem and I looked and looked and can't
     *      figure it out.
     *
     * @param string[] $src    One Replenish Detail record
     * @param string[] $dest   One line itenm for the PO
     */
    private function CopyStandardDimensionRecordNumbers($src, &$dest)
    {
        // The first row of fields are fetched from the database.
        // The second row can be entered by the customer.
        $fields = [ 'LOCATION', 'ITEMDIMKEY',    'WAREHOUSEDIMKEY',
                     'VENDORID',    'PROJECTID', 'CUSTOMERID', 'EMPLOYEEID', 'CLASSID', 'DEPARTMENT', 'CONTRACTID', 'ASSETID' ];

        foreach ($fields as $fieldName) {
            if (isset($src[$fieldName])) {
                list($dest[$fieldName]) = explode('--',$src[$fieldName]);
            }
        }
        $dest['DEPTKEY'] = $dest['DEPARTMENT'];
    }


    /**
     *  Create PO Transactions - create a PO transaction
     *
     * @param array  $params      overall values, filters, directives
     * @param array  $lastPO      the purchase order we are creating here (OUT)
     * @param array  $rows        all possible rows for all possible POs
     * @param array  $POLines     the PO lines to include on THIS PO
     * @param string $state       Pending or Submitted
     *
     * @return bool
     */
    private function CreatePOTransaction(&$params, &$lastPO, &$rows, $POLines, $state)
    {
        $row0     = $rows[ $POLines[0]];
        $memo     = "Replenishment run on " . GetCurrentDate( IADATE_USRFORMAT ) . " by " . GetMyLogin();
        list($vendorID) = explode('--', $row0['VENDORNAME']);

        $shipToRec       = $this->getShipToRecFromKey($row0['SHIPTOKEY']);

        $values = [
            'DOCPARID' => $params['TRANSACTION_DEFINITION'],
            'WHENCREATED' => $params['TRANSACTION_DATE'],
            'WHENPOSTED'  => $params['TRANSACTION_DATE'],   // I'm told this is aspirational
            'WHENDUE'     => '',                            // will be computed from the terms
            'CREATEDFROM' => '',
            'CUSTVENDID'  => $vendorID,
            'VENDORDOCNO' => '',                            // not available, we don't allow TDs that demand this
            'DOCNO'       => '',                            // will be supplied by PO code
            'PONUMBER'    => '',                            // will be supplied by PO code
            'TERM' => [
                'NAME' => $row0['VENDORTERM'],              // vendor term or TD term if not a vendor term
            ],
            'TERMKEY'     => $row0['TERMKEY'],              // this is the actual term record number
            'MESSAGE'     => $params['MESSAGE'] ?? '',
            'MEMO'        => $memo,
            'SHIPVIA'     => '',
            'BILLTO'      => '',
            'STATE'       => $state,
            'HEADER_VENDORID' => $vendorID,
            'SUPDOCID'    => '',
            'BASECURR'    => $this->getCurrencyForLocation( $row0['LOCATIONKEY'] ), // todo: for multi-ship, what do I use here? *****************************
            'CURRENCY'    => $row0['CURRENCY'],
            'EXCHRATEDATE' => $row0['EXCHANGE_DATE'],
            'EXCHRATETYPES' => ['NAME' => $row0['CURRENCY_EXCHANGE']],
            'BASE'        => $row0['BASE'],         // base currency
            'EXCHRATE'    => $row0['EXCHANGE_RATE'],
            'NOTE'        => "Created by Replenishment on " . GetCurrentDate(),
            'SHIPTO'      => $shipToRec,

            'FROMAPI_2.1' => true,                          // mimic xmlgw_router.2.1 for now
        ];

        // If we are using 'deliver to' (based on the preferences of POs), fill in the delever-to field
        if ($this->deliverToHeader != '') {
            $values['DELIVERTO']['CONTACTNAME'] = $this->deliverToHeader;   // the rest of the record is looked up via just the contact name inside document manager
        }

        $lineNo = 0;
        foreach ( $POLines as $POLine) {
             $entry = $rows[$POLine];

             $thisentry = [
                'LINE_NO'   => $lineNo++,
                'ITEMID'    => $entry['ITEM'],
                'ITEMDESC'  => $entry['ITEMNAME'],   // not really the description, but...
                'ITEMNAME'  => $entry['ITEMNAME'],
                'WAREHOUSE' => [
                    'LOCATION_NO' => $entry['WAREHOUSE'],
                    'NAME' => $entry['WAREHOUSENAME'],
                ],
                'UIQTY' => $entry['QUANTITY_TO_PURCHASE'],
                'UNIT' => $entry['UNITS_OF_MEASURE'],
                'UNITFACTOR' => ($entry['CONVFACTOR'] ?: 1.0),
                'TRX_PRICE' => $entry['PURCHASE_PRICE'],
                'TAXVALOVERRIDE' => '',
                'TAXABSVAL' => '',
                'LINETOTAL' => $entry['QUANTITY_TO_PURCHASE'],
                'LOCATION' => $entry['LOCATION'],
                'DEPARTMENT' => $entry['DEPARTMENT'],
                'MEMO' => '',
                'BILLABLE' => '',
                'PROJECTID' => '',
                'CUSTOMERID' => $entry['CUSTOMERDIMKEY'] ?? '',
                'VENDORID' => $entry['VENDORID'],
                'VENDORNAME' => $entry['VENDORNAME'],
                'EMPLOYEEID' => '',
                'CLASSID' => '',
                'CONTRACTID' => '',
                'SOURCE_DOCLINEKEY' => '',
                'TRACKINGENTRIES' => '',
                'FORM1099'     => (($entry['FORM1099TYPE'] != '' && $entry['FORM1099BOX'] != '') ? 'true' : 'false'),    // this is assumed when both type and box are present
                'FORM1099TYPE' => $entry['FORM1099TYPE'],
                'FORM1099BOX'  => $entry['FORM1099BOX'],
                'ASSETID'  => ''
            ];

            // if line-level delivery is enabled, then fill in the deliverto field
            if ($this->deliverToLine) {
                $thisentry['DELIVERTO']['CONTACTNAME'] = $entry['DELIVERTOKEY'];
            }

            // Copy regular dimensions
            $this->CopyStandardDimensionRecordNumbers($entry, $thisentry);

            // Copy custom dimensions
            $this->CopyCustomDimensions($entry, $thisentry);

            $values['ENTRIES'][] = $thisentry;
        }

        $ok = $this->podocumentMgr->add($values);

        $lastPO = $values;

        return $ok;
    }


    /**
     *  Try to get the exchange rate from the given currency exchange name.  If that doesn't work,
     *  try again with the Intacct Daily Rate
     *
     * @param string        $base       base currency like USD (depends on WAREHOUSE LOCATION)
     * @param string        $curr       to-currency like CAN
     * @param string        $effdate    effective date
     * @param string        $currName   name of exchange type
     * @param string|null   $warnings   warning messages from the desired exchange table
     *
     * @return float|bool
     */
    private function getExchangeRate($base, $curr, &$effdate, $currName, &$warnings)
    {
        $warnings               = null;
        $rate                   = 1.0;
        if ($base == $curr) {
            return $rate; // the same, no matter the exchange
        }

        $errorCheckpoint        = Globals::$g->gErr->Checkpoint();

        // First try:  Not the intacct daily rate?
        if ($currName != INTACCT_RATE) {
            // we've gone back and forth on this: should we fall back to the IDR?  Current pendulum swing: no.
            $rate = $this->exchMgr->GetTrxExchangeRateByTypeID($this->currencyExchangeID, $curr, $base, $effdate);
        } else {

            // Intacct rate only works for today or earlier
            if (SysDateCompare($effdate, GetCurrentDate()) > 0) {
                $effdate = GetCurrentDate();    // we can't predict the future, so default to today's rate.
            }
            $rate = $this->exchMgr->GetTrxExchangeRateByTypeID($this->currencyExchangeID, $curr, $base, $effdate);
        }
        // QA decision: ignore errors here, but toss the vendor/item/warehouse combo.
        if ($rate === false) {
            $poMessages = Globals::$g->gErr->errorStringsWithCorrections(true, 20, $errorCheckpoint);
            $poMessages = str_replace("\n", "; ", $poMessages);

            if (strlen($poMessages) >= self::MAX_ERROR_LENGTH) {
                $poMessages = substr($poMessages, 0, self::MAX_ERROR_LENGTH - 4) . '...';
            }
            $warnings = $poMessages;
            Globals::$g->gErr->Restore($errorCheckpoint);   // in case we threw an error, reset the error stack
        }
        return $rate;
    }




    /**
     *      validate for POs - given the array of item/warehouse/vendors, validate the parameters in the context of generateing POs.
     *
     * @param array $params
     * @param array $POs
     *
     * @return bool
     */
    private function validateForPOs(&$params, &$POs)
    {
        unset($params['std_buttons'], $params['DYNAMIC_HELP_INFORMATION']);  // artifact of the UI

        $wigs = array();
        $POs  = array();

        $ok = $this->validateAndCleanupValues( self::GENERATE_POS,$params );
        if ($ok) {
            BuildPRMaps();  // this is where the globals $deptmapno and $locmapno come from
            global $deptmapno, $locmapno;

            foreach ($params['ITEMS_ORDERING_INFO'] as $index => $row) {
                if (($row['INCLUDED'] === 'true') || ($row['INCLUDED'] === 'T')) {
                    if ($row['QUANTITY_TO_PURCHASE'] > 0) {
                        $line = (string)($index + 1);
                        if (!empty($row['DEPARTMENT'])) {
                            list($testThis) = explode('--',$row['DEPARTMENT']);
                            if(!$deptmapno[$testThis]) {
                                Globals::$g->gErr->addIAError(
                                    'INV-0786', __FILE__ . ":" . __LINE__,
                                    "On line $line, Department ID " . $row['DEPARTMENT'] . " is not compatible with your current department.",
                                    ['LINE' => $line, 'ROW_DEPARTMENT' => $row['DEPARTMENT']]
                                );
                                $ok = false;
                                break;
                            }
                        }
                        if (!empty($row['LOCATION'])) {     // from the dimensions dropdown
                            list($testThis) = explode('--',$row['LOCATION']);
                            if( !$locmapno[$testThis] ) {
                                Globals::$g->gErr->addIAError(
                                    'INV-0787', __FILE__ . ":" . __LINE__,
                                    "On line $line, Location ID " . $row['LOCATION'] . " is not compatible with your location of '" . $this->myLocationName . "'.",
                                    ['LINE' => $line, 'ROW_LOCATION' => $row['LOCATION'], 'MY_LOCATION_NAME' => $this->myLocationName]
                                );
                                $ok = false;
                                break;
                            }
                        }

                        $wig = $row['WAREHOUSE_ITEM_GROUP'];
                        if (isset($wigs[$wig])) {
                            $wigs = (string)($wigs[$wig]+1);
                            Globals::$g->gErr->addIAError(
                                'INV-0788', __FILE__ . ':' . __LINE__,
                                sprintf('Both rows %1$s and %2$s are selected, but they use different vendors for the same item and warehouse.  Deselect one row.', $line, (string)($wigs[$wig]+1)),
                                ['LINE' => $line, 'WIGS' => $wigs]
                            );
                            $ok = false;
                            break;
                        }
                        // look for currency warnings
                        if ($row['CURRENCY_WARNINGS'] != null) {
                            $msg = sprintf('On line %1$s, the selected vendor has a problem with currency translation: %2$s', $line, $row['CURRENCY_WARNINGS']);
                            Globals::$g->gErr->addIAError(
                                'INV-0789', __FILE__ . ":" . __LINE__,
                                $msg, ['LINE' => $line, 'ROW_CURRENCY_WARNINGS' => $row['CURRENCY_WARNINGS']]
                            );
                            $ok = false;
                            break;
                        }
                        $wigs[$wig] = $index;
                        $POs[$row['PROPOSED_PO']][] = $index;   // collect the list of items for each po
                    }
                }
            }
        }

        if ($ok) {
            if (count($wigs) == 0) {
                Globals::$g->gErr->addIAError('INV-0253', __FILE__ . ':' . __LINE__,
                    "To create purchase orders, select one or more items. Then try again.",[]);
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * update the record in the database
     *
     * @param array &$values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        if ( ! isset($values['SNAPSHOT'])) {
            Globals::$g->gErr->addIAError('INV-0254', __FILE__ . ':' . __LINE__,
                "Enter snapshot data in <Snapshot></Snapshot>", []);
            return false;
        }
        $snapShotData = $values['SNAPSHOT'];

        if (($values['CREATE_SNAPSHOT'] === 'true') || ($values['CREATE_SNAPSHOT'] === 'T')) {
            return $this->saveSnapshot( $values, $snapShotData );
        }
        if (($values['OFFLINE'] === 'true') || ($values['OFFLINE'] === 'T')) {
            return $this->generatePOsOffline( $values );
        }
        return $this->generatePOs($values, $snapShotData );
    }


    /**
     *  return any collected diagnostic information
     *
     * @return string       Any collected diagnostics
     */
    public function getDiagnostics()
    {
        return $this->diagnostics;
    }

}
