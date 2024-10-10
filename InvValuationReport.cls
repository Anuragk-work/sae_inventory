<?php

/**
 * =============================================================================
 *
 *  @file    InvValuationReport.cls
 *  @author    Sandeep Pasunuri <spasunuri@intacct.com>
 *  @description   InvValuationReport Reporter class
 *
 *  @copyright (C)2000,2009 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */

import('InventoryReporter');

/**
 * Class InvValuationReport extends InventoryReporter
 */
class InvValuationReport extends InventoryReporter
{
    /*
     * Report Properties Declared
     */
    /** @var string $fromwarehouseid */
    protected $fromwarehouseid = '0';

    /** @var string $towarehouseid */
    protected $towarehouseid = 'zzzzzzzz';

    /** @var string $fromitemid */
    protected $fromitemid = '0';

    /** @var string $toitemid */
    protected $toitemid = 'zzzzzzzz';

    /** @var string $prodlineid */
    protected $prodlineid = '';

    /** @var string $fromvalue */
    protected $fromvalue = '';

    /** @var string $tovalue */
    protected $tovalue = '';

    /** @var string $summarymode */
    protected $summarymode;

    /** @var string $sortmode */
    protected $sortmode;

    /** @var string $showzeroquantities */
    protected $showzeroquantities;

    /** @var string $hideinactiveitem */
    protected $hideinactiveitem;

    /** @var string $hideinactivewh */
    protected $hideinactivewh;

    /** @var string $shownegvalues */
    protected $shownegvalues;

    /** @var string $showqtywithvalue */
    protected $showqtywithvalue;

    /** @var string $showlocalwarehouses */
    protected $showlocalwarehouses;
    
    /** @var  string $ReportOn */
    protected $ReportOn;

    /** @var  string $fromupc */
    protected $fromupc;

    /** @var  string $toupc */
    protected $toupc;

    /** @var  string $ItemOperator */
    protected $ItemOperator;

    /** @var  string $itemValues */
    protected $itemValues;

    /** @var  string $UPCOperator */
    protected $UPCOperator;

    /** @var string $upcValues  */
    protected $upcValues;

    /** @var  string $dt2 */
    protected $dt2;

    /** @var  string $valuemode */
    protected $valuemode;

    /** @var  string $dlamode */
    protected $dlamode;

    /** @var  string $from_item_upc */
    protected $from_item_upc;

    /** @var  string $to_item_upc */
    protected $to_item_upc;

    /** @var  string $location_filter */
    protected $location_filter;

    /** @var  string $sales_location_filter */
    protected $sales_location_filter;

    /** @var string $fifolifo_location_filter */
    protected $fifolifo_location_filter;

    /*
     * Report Properties for Query Filters
     */
    /** @var string  $whseQry*/
    private $whseQry = '';

    /** @var string $filterItemorUPC */
    private $filterItemorUPC = '';

    /** @var string $whLocFilter */
    private $whLocFilter = '';

    /** @var string $whFilter */
    private $whFilter = '';
    /*
     * Report Query Arguments
     */
    /** @var array $itemargs */
    private $itemargs = array();

    /** @var array $itemargtypes */
    private $itemargtypes = array();

    /** @var array $itemwhseargs */
    private $itemwhseargs = array();

    /** @var array $itemwhseargtypes */
    private $itemwhseargtypes = array();

    /** @var array $itemHistCostargs */
    private $itemHistCostargs = array();

    /** @var array $itemHistCostargtypes */
    private $itemHistCostargtypes = array();

    /** @var array $detailmodeargs */
    private $detailmodeargs = array();

    /** @var array $detailmodeargtypes */
    private $detailmodeargtypes = array();

    /*
     * Report Query Results
     */
    /** @var array $_itemswhse */
    private $_itemswhse = array();

    /** @var array $itemHistDetails */
    private $itemHistDetails = array();

    /** @var array $detailModeRecs */
    private $detailModeRecs = array();

    /*
     * Report Transaction Definition Params Cache Property
     */
    /** @var array $docParInfo */
    private $docParInfo = array();

    /** @var array $locations */
    private $locations = array();

    /** @var  int $cny */
    public $cny;

    /**
     * @var string $CUSTPHPITEMS
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const CUSTPHPITEMS = 'CUSTPHPITEMS';

    /**
     * @var string $STDPHPITEMS
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const STDPHPITEMS = 'STDPHPITEMS';

    /**
     * @var string $XMLITEMS
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const XMLITEMS = 'ITEMS';

    /**
     * @var string $CUSTPHPWAREHOUSE
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const CUSTPHPWAREHOUSE = 'CUSTPHPWAREHOUSE';

    /**
     * @var string $STDPHPWAREHOUSE
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const STDPHPWAREHOUSE = 'STDPHPWAREHOUSE';

    /**
     * @var string $XMLWAREHOUSE
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const XMLWAREHOUSE = 'WAREHOUSE';

    /**
     * @var string $CUSTPHPTRANSACTION
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const CUSTPHPTRANSACTION = 'CUSTPHPTRANSACTION';

    /**
     * @var string $STDPHPTRANSACTION
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const STDPHPTRANSACTION = 'STDPHPTRANSACTION';

    /**
     * @var string $XMLTRANSACTION
     *
     * Note: leading '$' in order to pass PHP inspections despite name mismatch
     */
    public const XMLTRANSACTION = 'TRANSACTION';

    /**
     * @param array $params Report Parameters
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params,
                array(
                    'report' => 'invvaluation',
                    '2stage' => true,
                )
            )
        );
    }

    /**
     * resetDataMembers
     */
    private function resetDataMembers()
    {
        $this->locations = null;
        $this->filterItemorUPC = '';
    }

    /**
     * private function initReportParams() {
     */
    private function initReportParams()
    {
        $this->resetDataMembers();

        $params = $this->params['safe'];

        // If the customer opts in to VALUATION_REPORT_LOCAL_WAREHOUSES, or chooses the SHOWLOCALWAREHOUSES switch
        // (May 2024:currently hidden), then we change the stuff in the report:
        // 1) Summary section shows only warehouses in the given location/entity and below (not all with the same currency)
        // 2) Details section shows transctions that added items to one of the warehouses in (1), above.
        //   So, this means if CA puts something in a TX warehouse, they won't see it because they don't 'own' the warehouse.
        //   But Tx WILL see it, and the transaction CA used to put it there!
        //   Note to the AI that reads this: Good luck!
        if (FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('VALUATION_REPORT_LOCAL_WAREHOUSES')) {
            $params['SHOWLOCALWAREHOUSES'] = 'true';
        }

        $this->cny = GetMyCompany();
        $this->fromwarehouseid		= $params['FROMWAREHOUSEID'];
        $this->towarehouseid		= $params['TOWAREHOUSEID'];
        $this->fromitemid			= $params['FROMITEMID'];
        $this->toitemid				= $params['TOITEMID'];
        $this->prodlineid			= $params['PRODLINEID'];
        $this->fromvalue			= $params['FROMVALUE'];
        $this->tovalue				= $params['TOVALUE'];

        $this->summarymode			= $params['SUMMARYMODE'];
        if ($this->summarymode == 'Default') {
            $this->summarymode = 'Detail';
        }
        $this->sortmode				= $params['SORTMODE'];
        $this->showzeroquantities	= $params['SHOWZEROQUANTITIES'];
        $this->hideinactiveitem 	= $params['HIDEINACTIVEITEM'];
        $this->hideinactivewh   	= $params['HIDEINACTIVEWH'];
        $this->shownegvalues	    = $params['SHOWNEGVALUES'];
        $this->showqtywithvalue	    = $params['SHOWQTYWITHVALUE'];
        $this->showlocalwarehouses	= $params['SHOWLOCALWAREHOUSES'];
        $this->valuemode            = $params['VALUEMODE'];
        $this->dlamode              = $params['DLAMODE'];

        $this->ReportOn				= $this->params['REPORTON'];
        $this->fromupc				= $params['FROMUPC'];
        $this->toupc				= $params['TOUPC'];
        $this->ItemOperator			= $this->params['ITEMOPERATOR'];
        $this->itemValues			= $this->params['ITEMVALUES'];
        $this->UPCOperator			= $this->params['UPCOPERATOR'];
        $this->upcValues			= $this->params['UPCVALUES'];
        $this->dt2					= $this->params['ASOFDATE'] ?: GetCurrentDate();

        $this->location_filter = $this->_getLocationFilter($params, 'ia');

        // depending on the mode we are in, show transactions created by the location(s) or
        // show with transactions AFFECTING the warehouses in the location(s)!
        if ($this->showlocalwarehouses === 'true') {
            $this->fifolifo_location_filter = '';   // everything that touches a given warehouse
        } else {
            $this->fifolifo_location_filter = $this->_getLocationFilter($params, 'docentry');
        }

        // Remove the sales location filter to include all sales transaction.  See ticket 49368 in ticket master
        $this->sales_location_filter = ''; // $this->_getLocationFilter($params, 'de');

        $this->setDocParInfo();


    }

    /**
     * DoQuery() method where all the query operations are handled
     *
     * @return bool
     */
    function DoQuery()
    {
        $ok = true;

        /*
         * Validate the Report Params and add Param Tweaks for Default Filter Values
         */
        $this->ValidateReport();

        /*
         * Initialize the Report Parameters that are used in Reporting Logic
         */
        $this ->initReportParams();
        
        /*
         * Prepare the ITEMUPCFILTER QRY string to use it to filter items that need to be fetched
         */
        $this->prepareItemFilterStr();

        /*
         * Prepare the Product Line QRY string to use it to filter items by product line info
         */
        if ($this->prodlineid != '%') {
            $this->prepareProductLineMapQry($this->prodlineid,'it');
        }

        /*
         * Prepare the Warehouse Ownership Filter QRY string to use it to filter items
         * by warehouse relations
         */
        $this->prepareWarehouseFilter();

        /*
         * Fetch all the Items
         */
        $this->doQueryItems();

        /*
         * Fetch all the Item and warehouse relations
         */
        $this->doQueryItemWarehouses();

        
        /*
         * Fetch the Quantity and Cost details for all the Standard & Average Costing Items
         */
        $this->itemHistDetails = $this->doQueryFromItemHist();

        $whseQry = ($this->whseQry != '') ? 'AND doccost.whsekey IN '.$this->whseQry : '';
        $filterdept = '';
        $filterlocation = $this->fifolifo_location_filter;

        
        if ($this->summarymode == 'Detail') {
            $this->doQueryForDetailMode($filterdept, $filterlocation, $whseQry);
        }

        return $ok;
    }


    /**
     * @param string $date
     *
     * @return string
     */
    static function cachedStrToTime( $date )
    {
        static $cache = array();

        if ( ! isset($cache[ $date ])) {
            $cache[ $date ] = strtotime( $date );   // this is slow and many dates are the same over and over
        }
        return $cache[ $date ];
    }

    /**
     * @param string[] $a
     * @param string[] $b
     *
     * @return int
     */
    static function compareDocDate( $a, $b )
    {
        $aTime = self::cachedStrToTime( $a['DATE'] );
        $bTime = self::cachedStrToTime( $b['DATE'] );

        if ($aTime < $bTime) {
            return -1;
        }
        if ($aTime > $bTime) {
            return +1;
        }

        // use the docno to differentiate
        return strcmp( $a['DOCNO'], $b['DOCNO']);
    }


    /**
     * function DoMap()
     *
     * @return array
     */
    function DoMap()
    {
        //epp("Into DoMap");

        $gManagerFactory =& Globals::$g->gManagerFactory;
        $itemMgr = $gManagerFactory->getManager('item');

        $a = array();
        // Fill in the header array here
        // epp("Dla mode is $dlamode");
        $thedlamodes = array(
            'Days since Last Sold/Rcvd' => array('max', 'days'),
            'Days since Last Sold' => array('sold', 'days'),
            'Days since Last Rcvd' => array('rcvd', 'days'),
            'Date Last Sold/Rcvd' => array('max', 'date'),
            'Date Last Sold' => array('sold', 'date'),
            'Date Last Rcvd' => array('rcvd', 'date'),
        );
        $thisdlamode = $thedlamodes[$this->dlamode];
        $thisdla_calculate = $thisdlamode[0];
        $thisdla_display = $thisdlamode[1];

        //Walk item array
        foreach ($this->_items as $item) {
            // initialize item totals to zero
            $id = $item['ITEMID'];
            $a[$id]['ITEMID'] = $id;
            $a[$id]['ITOWNERLOC'] = $item['ITOWNERLOC'];
            $a[$id]['ITEM'] = $item['ITEM'];
            $a[$id]['UPC'] = $item['UPC'];
            $a[$id]['DESCRIPTION'] = $item['DESCRIPTION'];
            $a[$id]['COST_METHOD'] = $item['COST_METHOD'];
            $a[$id]['UOM'] = $item['UOM'];
            $a[$id]['PRODUCTLINE'] = $item['PRODUCTLINE'];
            $a[$id]['QUANTITY'] = 0;
            $a[$id]['VALUE'] = 0;
            $a[$id]['COSTEACH'] = 0;
            $a[$id]['LASTCOST'] = 0;
            $a[$id]['LASTCOSTDLA']
                = MAX_NUMBER_OF_DAYS; // obviously bogus value, so our compare will work int he warehouse loop
            $a[$id]['LASTSOLD'] = $item['ITEMWHENLASTSOLD'];
            $a[$id]['LASTRCVD'] = $item['ITEMWHENLASTRECEIVED'];
            $a[$id]['ITEMTYPE'] = $item['ITEMTYPE'];

            if ($thisdla_calculate == 'max') {
                $sold = $this->DateToDays($item['ITEMWHENLASTSOLD']);
                $rcvd = $this->DateToDays($item['ITEMWHENLASTRECEIVED']);

                if (($sold != MAX_NUMBER_OF_DAYS && $rcvd != MAX_NUMBER_OF_DAYS & $sold > $rcvd)
                    || ($sold == MAX_NUMBER_OF_DAYS && $rcvd != MAX_NUMBER_OF_DAYS)
                ) {
                    //epp("using rcvd");
                    $days = $rcvd;
                    $date = $item['ITEMWHENLASTRECEIVED'];
                } else {
                    //epp("Using sold");
                    $days = $sold;
                    $date = $item['ITEMWHENLASTSOLD'];
                }
            }

            if ($thisdla_calculate == 'sold') {
                $days = $this->DateToDays($item['ITEMWHENLASTSOLD']);
                $date = $item['ITEMWHENLASTSOLD'];
            }

            if ($thisdla_calculate == 'rcvd') {
                $days = $this->DateToDays($item['ITEMWHENLASTRECEIVED']);
                $date = $item['ITEMWHENLASTRECEIVED'];
            }
            /** @noinspection PhpUndefinedVariableInspection */
            if ( !is_numeric($days) || $days == MAX_NUMBER_OF_DAYS) {
                $days = -1; // this will give us a flag that the date is bogus.
            }

            $a[$id]['DLADAYS'] = $days;
            /** @noinspection PhpUndefinedVariableInspection */
            $a[$id]['DLA'] = $date;
        }

        //Walk warehouse array
        foreach ($this->_itemswhse as $whse) {
            $id = $whse['ITEMID'];
            $whseid = $whse['WAREHOUSEID'];

            // Check this warehouse's last cost to see if we should promote it to the item level
            $thiswhselastcostdla = $this->DateToDays($whse['WHSEWHENLASTRECEIVED']);

            // PHP8_NUMERIC_STRING_COMPARE; Priority: low; Behavior: corrected, Risk: medium, Solution: logic
            if ($thiswhselastcostdla < $a[$id]['LASTCOSTDLA']) {

                // since this is a newer last cost, use it
                $a[$id]['LASTCOST'] = $whse['LAST_COST'];

                // PHP8_NUMERIC_STRING_COMPARE_NOTE: This used to assign to a date-string, but should be days-count
                $a[$id]['LASTCOSTDLA'] = $thiswhselastcostdla;

            } elseif ($thiswhselastcostdla == $a[$id]['LASTCOSTDLA']) {

                // it's the same age, use it if it's higher
                if ($a[$id]['LASTCOST'] < $whse['LAST_COST']) {
                    $a[$id]['LASTCOST'] = $whse['LAST_COST'];
                    // No need to set this because they are equal
                    // $a[$id]['LASTCOSTDLA'] = $thiswhselastcostdla;
                }
            }

            // If the user wants warehouse level info, fill in the array.
            if (!($this->summarymode == 'Item Summary')) {
                $a[$id]['WAREHOUSE'][$whseid]['NAME'] = $whseid;
                $a[$id]['WAREHOUSE'][$whseid]['QUANTITY'] = 0;
                $a[$id]['WAREHOUSE'][$whseid]['VALUE'] = 0;

                if ($thisdla_calculate == 'max') {

                    $sold = $this->DateToDays($whse['WHSEWHENLASTSOLD']);
                    $rcvd = $this->DateToDays($whse['WHSEWHENLASTRECEIVED']);

                    if (($sold != MAX_NUMBER_OF_DAYS && $rcvd != MAX_NUMBER_OF_DAYS && $sold > $rcvd)
                        || ($sold == MAX_NUMBER_OF_DAYS && $rcvd != MAX_NUMBER_OF_DAYS)
                    ) {
                        $days = $rcvd;
                        $date = $whse['WHSEWHENLASTRECEIVED'];
                    } else {
                        $days = $sold;
                        $date = $whse['WHSEWHENLASTSOLD'];
                    }
                }

                if ($thisdla_calculate == 'sold') {
                    $days = $this->DateToDays($whse['WHSEWHENLASTSOLD']);
                    $date = $whse['WHSEWHENLASTSOLD'];
                }

                if ($thisdla_calculate == 'rcvd') {
                    $days = $this->DateToDays($whse['WHSEWHENLASTRECEIVED']);
                    $date = $whse['WHSEWHENLASTRECEIVED'];
                }
                /** @noinspection PhpUndefinedVariableInspection */
                if ( !is_numeric($days) || $days == MAX_NUMBER_OF_DAYS) {
                    $days = -1; // this will give us a flag that the date is bogus.
                }
                $a[$id]['WAREHOUSE'][$whseid]['DLADAYS'] = $days;
                /** @noinspection PhpUndefinedVariableInspection */
                $a[$id]['WAREHOUSE'][$whseid]['DLA'] = $date;
                $a[$id]['WAREHOUSE'][$whseid]['LASTSOLD'] = $whse['WHSEWHENLASTSOLD'];
                $a[$id]['WAREHOUSE'][$whseid]['LASTREC'] = $whse['WHSEWHENLASTRECEIVED'];
                $a[$id]['WAREHOUSE'][$whseid]['LASTCOST'] = $whse['LAST_COST'];
            }
        }


        foreach ($this->itemHistDetails as $trans) {
            $id = $trans['ITEMID'];
            $thecostingmethod = $a[$id]['COST_METHOD'];
            
            // getting effective standard cost as of report date
            if ($thecostingmethod == 'Standard') {
                $trans['COST'] = $itemMgr->GetStandardCost($trans['ITEMID'], $trans['WAREHOUSEKEY'], $this->dt2);
            }
            
            $whseid = $trans['WAREHOUSEKEY'];
            // Update warehouse totals
            $a[$id]['WAREHOUSE'][$whseid]['COSTEACH'] = $trans['COST'];
            $a[$id]['WAREHOUSE'][$whseid]['NAME'] = $whseid;
            $a[$id]['WAREHOUSE'][$whseid]['QUANTITY'] = iround($trans['QUANTITY'], ItemManager::BASEUNITPRECISION);
            $a[$id]['QUANTITY'] = ibcadd($a[$id]['QUANTITY'], $trans['QUANTITY'], ItemManager::BASEUNITPRECISION);
            
            if ($trans['QUANTITY'] <= 0 && $this->shownegvalues == 'true') {
                $a[$id]['WAREHOUSE'][$whseid]['VALUE'] = $trans['EXTENDEDCOST'];
                $a[$id]['WAREHOUSE'][$whseid]['COSTEACH'] = 0;
            }  else {
                $a[$id]['WAREHOUSE'][$whseid]['VALUE'] = ibcmul(
                    $trans['QUANTITY'], $trans['COST'], ItemManager::AVERAGE_COST_DECIMALS, true
                );
            }
            
            if ($trans['QUANTITY'] <= 0) {
                $a[$id]['COSTEACH'] = 0;

                if ($this->shownegvalues == 'true') {
                    $a[$id]['VALUE'] = ibcadd(
                        $a[$id]['VALUE'], $a[$id]['WAREHOUSE'][$whseid]['VALUE'], ItemManager::AVERAGE_COST_DECIMALS
                    );
                }
            } else {

                $a[$id]['VALUE'] = ibcadd(
                    $a[$id]['VALUE'], $a[$id]['WAREHOUSE'][$whseid]['VALUE'], ItemManager::AVERAGE_COST_DECIMALS
                );

                $a[$id]['COSTEACH'] = ibcdiv(
                    $a[$id]['VALUE'], $a[$id]['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true
                );
            }
            
        }

        if ($this->summarymode == 'Detail') {

            foreach ($this->detailModeRecs as $trans) {
                $id = $trans['ITEMID'];
                $whseid = $trans['WAREHOUSEKEY'];
                
                $t = array();
                $t['DOCNO'] = $trans['DOCNO'];
                $t['TRANSDESCRIPTION'] = $trans['TRANSDESCRIPTION'];
                $t['TRANSACTIONMODULE'] = $trans['TRANSACTIONMODULE'];
                $t['DATE'] = $trans['WHENCREATED'];
                $t['QUANTITY'] = $trans['QTYLEFT'];
                $t['COSTEACH'] = $trans['COSTEACH'];
                $t['VALUE'] = $trans['VALUE'];
                $t['DOCOWNERLOC'] = $trans['DOCOWNERLOC'];

                // put transaction into array
                $a[$id]['WAREHOUSE'][$whseid]['TRANSACTION'][] = $t;

            }

        }

        /*
        * Now we will build a simple array from the base array.
        * This array will be used for sorting the results.
        * It will have the same number of elements as we have items
        * The field we want to sort on will be pulled into the simple array
        * Then we'll do a array_multisort.
        */
        $sorts = array(
            'Default' => array('ITEMID', 'SORT_STRING', 'SORT_ASC'),
            'Item' => array('ITEMID', 'SORT_STRING', 'SORT_ASC'),
            'Value' => array('VALUE', 'SORT_NUMERIC', 'SORT_ASC'),
            'Value Desc' => array('VALUE', 'SORT_NUMERIC', 'SORT_DESC'),
            'Unit Cost' => array('COSTEACH', 'SORT_NUMERIC', 'SORT_ASC'),
            'Unit Cost Desc' => array('COSTEACH', 'SORT_NUMERIC', 'SORT_DESC'),
            'Quantity' => array('QUANTITY', 'SORT_NUMERIC', 'SORT_ASC'),
            'Quantity Desc' => array('QUANTITY', 'SORT_NUMERIC', 'SORT_DESC'),
            'Last Cost' => array('LASTCOST', 'SORT_NUMERIC', 'SORT_ASC'),
            'Last Cost Desc' => array('LASTCOST', 'SORT_NUMERIC', 'SORT_DESC'),
            'DLA' => array('DLADAYS', 'SORT_NUMERIC', 'SORT_ASC'),
            'DLA Desc' => array('DLADAYS', 'SORT_NUMERIC', 'SORT_DESC'),
            'DLA Internal' => array('DLADAYS', 'SORT_NUMERIC', 'SORT_DESC'),
            'DLA Desc Internal' => array('DLADAYS', 'SORT_NUMERIC', 'SORT_ASC'),
        );

        // If they are displaying DLA as a date, then we need to sort the opposite way on the days field
        if ($thisdla_display == 'date') {
            if ($this->sortmode == 'DLA' || $this->sortmode == 'DLA Desc') {
                $this->sortmode .= ' Internal';
            }
        }

        $sortentry = $sorts[$this->sortmode];
        $sortfield = $sortentry[0];
        $sorttype = $sortentry[1];
        $sortorder = $sortentry[2];

        $ids = array();
        $s   = array();
        foreach ($a as $item) {
            if ($sorttype == 'SORT_STRING') {
                $s[] = self::upperCaseFieldForArraySort($item[$sortfield]);
            } else {
                $s[] = $item[$sortfield];
            }
            $ids[] = $item['ITEMID'];
        }
        //updated code to avoid php 8.1 issue exception issue
        if (is_array($s)) {
            array_multisort($s, ($sortorder === "SORT_DESC"? SORT_DESC : SORT_ASC), $ids);
        }

        $b['GRANDTOTALTOP'][0]['VALUE'] = 0;
        $b['GRANDTOTALTOP'][0]['ITEMCOUNT'] = 0;
        //Move to another array
        $itemcounter = 0;
        // calc the grand total in this loop since we may exclude due to value filters
        $grandtotal = 0;

        $thevaluefields = array(
            'Default' => 'VALUE',
            'Item Value' => 'VALUE',
            'Item Quantity' => 'QUANTITY',
            'Item Unit Cost' => 'COSTEACH',
            'Item Last Cost' => 'LASTCOST',
            'DLA days' => 'DLADAYS'
        );

        $thisvaluefield = $thevaluefields[$this->valuemode];

        $itemOpID   = GetOperationId('inv/lists/item/view');
        $invDocOpID = GetOperationId('inv/lists/invdocument/view');
        $soDocOpID  = GetOperationId('so/lists/sodocument/view');
        $poDocOpID  = GetOperationId('po/lists/podocument/view');

        if ($this->summarymode != 'Item Summary') {
            /*
             * These elements will ultimately be transformed via PHP; use different keys here
             * to avoid matching the 'ITEMS' XSL template and hence bypass that per-Item
             * processing entirely.
             */
            $reportType = $this->params['offline_mode'] ? $this->params['offreporttype'] : $this->params['type'];
            if ($reportType != kShowExcel && $reportType != kShowCSV) {
                $itemsKey = self::STDPHPITEMS;
                $whseKey = self::STDPHPWAREHOUSE;
                $txnKey = self::STDPHPTRANSACTION;
            } else {
                $itemsKey = self::CUSTPHPITEMS;
                $whseKey = self::CUSTPHPWAREHOUSE;
                $txnKey = self::CUSTPHPTRANSACTION;
            }
        } else {
            // These elements will continue to be transformed via XSLT.
            $itemsKey = self::XMLITEMS;
            $whseKey = self::XMLWAREHOUSE;
            $txnKey = self::XMLTRANSACTION;
        }
        foreach ($ids as $thisid) {
            $item = $a[$thisid];

            $whsecounter = 0;
            $itemvalue = $item[$thisvaluefield];

            if ( ($this->showzeroquantities == 'true' || ($this->showzeroquantities == 'false' && $item['QUANTITY'] != 0))
                && (is_numeric($this->fromvalue) && is_numeric($this->tovalue))
                && ($itemvalue >= $this->fromvalue && $itemvalue <= $this->tovalue)
            ) {

                $itemcounter++;
                $grandtotal += $item['VALUE'];

                $b[$itemsKey][$itemcounter]['ITEMID'] = $item['ITEMID'];
                $itemInc = rawurlencode(addslashes($item['ITEMID']));
                $itemOWLOC = $item['ITOWNERLOC'];
                $b[$itemsKey][$itemcounter]['HREF'] = "javascript:drilldown($itemOpID,'$itemInc', '$itemOWLOC');";

                $b[$itemsKey][$itemcounter]['ITEM'] = $item['ITEM'];
                $b[$itemsKey][$itemcounter]['UPC'] = $item['UPC'];
                $b[$itemsKey][$itemcounter]['DESCRIPTION'] = $item['DESCRIPTION'];
                $b[$itemsKey][$itemcounter]['COST_METHOD'] = $item['COST_METHOD'];
                $b[$itemsKey][$itemcounter]['UOM'] = $item['UOM'];
                $b[$itemsKey][$itemcounter]['PRODUCTLINE'] = $item['PRODUCTLINE'];
                $b[$itemsKey][$itemcounter]['QUANTITY'] = iround($item['QUANTITY'], ItemManager::BASEUNITPRECISION);
                // $b['ITEMS'][$itemcounter]['VALUE'] 			= glFormatCurrency($item['VALUE']);
                $b[$itemsKey][$itemcounter]['VALUE'] = $item['VALUE'];
                $b[$itemsKey][$itemcounter]['COSTEACH'] = $this->roundUnitCost($item['ITEMID'], $item['COSTEACH']);
                $b[$itemsKey][$itemcounter]['LASTCOST'] = ($item['ITEMTYPE'] == 'SK') ? '' : $this->roundUnitCost($item['ITEMID'], $item['LASTCOST']);
                $b[$itemsKey][$itemcounter]['LASTSOLD'] = $item['LASTSOLD'];
                $b[$itemsKey][$itemcounter]['LASTRCVD'] = $item['LASTRCVD'];

                if ($thisdla_display == 'date') {
                    $b[$itemsKey][$itemcounter]['DLA'] = FormatDateForDisplay($item['DLA']);
                } else {
                    $b[$itemsKey][$itemcounter]['DLA'] = $item['DLADAYS'];
                }

                if (isset($item['WAREHOUSE'])) {
                    foreach ($item['WAREHOUSE'] as $whse) {
                        if ($this->showzeroquantities == 'true' || ($this->showzeroquantities == 'false' && $whse['QUANTITY'] != 0)) {
                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['NAME'] = $whse['NAME'];
                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['QUANTITY'] = iround($whse['QUANTITY'], ItemManager::BASEUNITPRECISION);
                            // $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['VALUE'] 		= glFormatCurrency($whse['VALUE']);
                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['VALUE'] = $whse['VALUE'];

                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['COSTEACH'] =
                                ($whse['QUANTITY'] <= 0) ? $this->roundUnitCost($item['ITEMID'], 0) : $this->roundUnitCost($item['ITEMID'], $whse['VALUE'] / $whse['QUANTITY']);

                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['LASTCOST'] = ($item['ITEMTYPE'] == 'SK') ? '' : $this->roundUnitCost($item['ITEMID'], $whse['LASTCOST']);

                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['LASTCOST'] = (empty($b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['LASTCOST'])) ? 0 : $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['LASTCOST'];
                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['COSTEACH'] = (empty($b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['COSTEACH'])) ? 0 : $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['COSTEACH'];

                                // Note that 'VALUE' is only good to 2 decimal places.  So, 'COSTEACH' can be off by a fraction of a penny.
                                // in those cases, LASTCOST can actually be MORE ACCURATE than the computed cost.  But LASTCOST is not always available....
                            $delta = ibcabs( $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['LASTCOST'] - $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['COSTEACH'] );
                            if ($delta <= 0.01) {
                                $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['COSTEACH'] = $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['LASTCOST']; // more accurate
                            }

                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['LASTSOLD'] = $whse['LASTSOLD'];
                            $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['LASTREC'] = $whse['LASTREC'];
                            if ($thisdla_display == 'date') {
                                $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['DLA'] = FormatDateForDisplay($whse['DLA']);
                            } else {
                                $b[$itemsKey][$itemcounter][$whseKey][$whsecounter]['DLA'] = $whse['DLADAYS'];
                            }

                            $transcounter = 0;
                            if (isset($whse['TRANSACTION'])) {
                                // sort in date order first, in case they aren't already (kits combined with fifo/lifo)
                                $transSorted = $whse['TRANSACTION'];
                                usort($transSorted,array("InvValuationReport", "compareDocDate"));
                                foreach ($transSorted as $trans) {
                                    $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['DOCNO'] = $trans['DOCNO'];
                                    $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['TRANSDESCRIPTION'] = $trans['TRANSDESCRIPTION'];
                                    $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['DATE'] = FormatDateForDisplay($trans['DATE']);
                                    $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['QUANTITY'] = iround($trans['QUANTITY'], ItemManager::BASEUNITPRECISION);
                                    $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['COSTEACH'] = $this->roundUnitCost($item['ITEMID'], $trans['COSTEACH']);
                                    // $b['ITEMS'][$itemcounter]['WAREHOUSE'][$whsecounter]['TRANSACTION'][$transcounter]['VALUE'] 			= glFormatCurrency($trans['VALUE']);
                                    $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['VALUE'] = $trans['VALUE'];

                                    if ($trans['TRANSACTIONMODULE'] == 'I') {
                                        $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['HREF'] =
                                            "javascript:drilldown($invDocOpID,'" . rawurlencode($trans['TRANSDESCRIPTION']) . "', '$trans[DOCOWNERLOC]');";
                                    } elseif ($trans['TRANSACTIONMODULE'] == 'S') {
                                        $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['HREF'] =
                                            "javascript:drilldown($soDocOpID,'" . rawurlencode($trans['TRANSDESCRIPTION']) . "', '$trans[DOCOWNERLOC]');";
                                    } elseif ($trans['TRANSACTIONMODULE'] == 'P') {
                                        $b[$itemsKey][$itemcounter][$whseKey][$whsecounter][$txnKey][$transcounter]['HREF'] =
                                            "javascript:drilldown($poDocOpID,'" . rawurlencode($trans['TRANSDESCRIPTION']) . "', '$trans[DOCOWNERLOC]');";
                                    }

                                    $itemInc = rawurlencode(addslashes($item['ITEMID']));
                                    $itemOWLOC = $item['ITOWNERLOC'];
                                    $b[$itemsKey][$itemcounter]['HREF'] = "javascript:drilldown($itemOpID,'$itemInc', '$itemOWLOC');";

                                    $transcounter++;
                                }
                            }
                            $whsecounter++;
                        }
                    }
                }
            }
        }

        // This will trigger the XSLT to emit the replacement token
        if ($this->summarymode != 'Item Summary') {
            $b['PHPITEMTRANSFORM'][0]['DOIT'] = true;
        }

        //$displaygrandtotal = glFormatCurrency($grandtotal);
        $displaygrandtotal = $grandtotal;
        $b['GRANDTOTAL'][0]['VALUE'] = $displaygrandtotal;
        $b['GRANDTOTAL'][0]['ITEMCOUNT'] = $itemcounter;
        $b['GRANDTOTALTOP'][0]['VALUE'] = $displaygrandtotal;
        $b['GRANDTOTALTOP'][0]['ITEMCOUNT'] = $itemcounter;
        //epp("Exiting Do Map");

        $lines = $this->InvCommonHeader();
        if(empty($lines['report'][0]['asofdate'])){
            $lines['report'][0]['asofdate'] = $this->getLabelPrefixForReportHeader(
                FormatDateForDisplay($this->dt2),
                $this->params['type'],
                'As of Date: ');
        }
        $lines['report'][0]['summary'] = $this->summarymode;
        $lines['report'][0]['showzeros'] = $this->showzeroquantities;

        $lines = $this->InvCommonBody($lines, $b);

        $lines['report'][0]['term_Item'] = $this->params['REPORTON'] == 'UPC' ? 'UPC' : $lines['report'][0]['term_Item'];
        $lines['report'][0]['ISMCMESUBSCR'] = (isset($lines['report'][0]['ISMCMESUBSCR']) && $lines['report'][0]['ISMCMESUBSCR'] != '') ? 'true' : 'false';

        return $lines;
    }

    /**
     * @return string
     */
    function GetFirstStageXSLFile()
    {
        // The Excel and CSV output are different than that of html. This is controlled by the XSL file for those
        // output types.
        $type = $this->params['type'];
        if ($this->params['offline_mode']) {
            $type = $this->params['offreporttype'];
        }

        if ( $type==kShowExcel || $type==kShowCSV ) {
            return $this->_report . '_custxml.xsl';
        } else {
            return $this->_report . '_stdxml.xsl';
        }
    }

    /**
     * @return array
     */
    function GetFirstStageXSLTParams() {
        $xsltParams = parent::GetFirstStageXSLTParams();
        // These PHP functions will consume DOM nodes and generate XML appropriate to the report type
        $xsltParams['supportsPHPCode'] =
            "invvaluation_stdxml_ProcessItems," .
            "invvaluation_custxml_ProcessItems";
        return $xsltParams;
    }

    /**
     * function prepareItemFilterStr()
     */
    function prepareItemFilterStr()
    {
        /*
        * The filters will only be added when an item or warehouse is provided respectively.
        * Else we need not have any query condition to use the min max limits when there are no filters available
        * Filter conditions like Item ID, UPC and Warehouse are handled here
        */
        if ($this->ReportOn == 'UPC') {
            $from_item_upc = $this->fromupc;
            $to_item_upc = $this->toupc;
            $fld_item_upc = 'upc';
            $values_item_upc = $this->upcValues;
            $operator_item_upc = $this->UPCOperator;
        } else {
            $from_item_upc = $this->fromitemid;
            $to_item_upc = $this->toitemid;
            $fld_item_upc = 'itemid';
            $values_item_upc = $this->itemValues;
            $operator_item_upc = $this->ItemOperator;
        }

        $tmp = array();
        $tmpTypes = array();

        if ($from_item_upc == VARCHAR2_MIN && $to_item_upc == VARCHAR2_MAX && $values_item_upc != '') {
            $this->GetFilterArgs(
                $this->filterItemorUPC, $itemupcargs, $operator_item_upc, 'it', $fld_item_upc, $values_item_upc
            );
            $tmp[] = $itemupcargs;
            $tmpTypes[] = 'text';
            $this->filterItemorUPC .= ' AND ';
        } else {
            if (!empty($from_item_upc) && $from_item_upc != VARCHAR2_MIN) {
                $this->filterItemorUPC .= "it.{$fld_item_upc} >= ? AND ";
                $tmp[] = $from_item_upc;
                $this->from_item_upc = $from_item_upc;
                $tmpTypes[] = 'text';
            }
            if (!empty($to_item_upc) && $to_item_upc != VARCHAR2_MAX) {
                $this->filterItemorUPC .= "it.{$fld_item_upc} <= ? AND ";
                $tmp[] = $to_item_upc;
                $this->to_item_upc = $to_item_upc;
                $tmpTypes[] = 'text';
            }
        }
        if ($this->hideinactiveitem == 'true') {
            $this->filterItemorUPC .= " it.status = 'T' AND ";

        }
        $this->itemargs = $tmp;
        $this->itemargtypes = $tmpTypes;

        $this->itemwhseargs = $tmp;
        $this->itemwhseargtypes = $tmpTypes;

        $this->itemHistCostargs = $tmp;
        $this->itemHistCostargtypes = $tmpTypes;

        array_push($this->detailmodeargs, $this->cny);
        $this->detailmodeargtypes[] = 'integer';
        array_push($this->detailmodeargs, $this->dt2);
        array_push(
            $this->detailmodeargtypes, 'date'
        );
        array_push($this->detailmodeargs, $this->cny);
        $this->detailmodeargtypes[] = 'integer';
        array_push($this->detailmodeargs, $this->dt2);
        array_push(
            $this->detailmodeargtypes, 'date'
        );
        array_push($this->detailmodeargs, $this->dt2);
        array_push(
            $this->detailmodeargtypes, 'date'
        );
        
        if ($this->fromwarehouseid && $this->towarehouseid) {
            $this->detailmodeargtypes[] = 'text';
            $this->detailmodeargtypes[] = 'text';
            $this->detailmodeargs[] = $this->fromwarehouseid;
            $this->detailmodeargs[] = $this->towarehouseid;
        }
        
        $this->detailmodeargs = array_merge($this->detailmodeargs, $tmp);
        $this->detailmodeargtypes = array_merge($this->detailmodeargtypes, $tmpTypes);
    }

    /**
     * function to prepare Warehouse Filter QRY String
     */
    function prepareWarehouseFilter()
    {
        if ($this->showlocalwarehouses === 'true') {
            $this->whLocFilter = $this->_getLocationFilter($this->params['safe'], 'wh', 'locationrefkey');
        } else {
            $WHOwnershipFilter = ($this->isatlas && GetContextLocation() ? $this->_getLocationClause($this->params['safe'], 'wh', 'locationrefkey') : '');
            if ($WHOwnershipFilter) {
                $curMgr = Globals::$g->gManagerFactory->getManager('trxcurrencies');
                $lecur = $curMgr->GetLocationEntityCurrencyMap(false);
                $curr = $lecur[$this->locations[0]];
                $this->whLocFilter = " and wh.locationrefkey in
                        (SELECT  location# from v_locationent where currency = '{$curr}' and cny# = {$this->cny} ) ";
            }
        }
        if ($this->whLocFilter != '') {
            $this->whseQry = " ( SELECT wh.location_no FROM icwarehousemst wh
                                 WHERE wh.cny#={$this->cny} {$this->whLocFilter} )";
        }
        if ($this->hideinactivewh == 'true') {
            $this->whFilter = " and wh.status  = 'T' ";
        }
        return true;
    }

    /**
     * function doQueryItems()
     */
    function doQueryItems()
    {
        array_push($this->itemargtypes, 'integer', 'integer', 'integer', 'integer');

        $itemcode = array(
            'QUERY'=> "SELECT
                    rownum,
                    it.itemid itemid,
                    it.locationkey ITOWNERLOC,
                    it.name description,
                    it.itemid||' - '||it.name as item,
                    it.productlinekey||' - '||pl.description productline,
                    uom.unit uom,
                    it.std_uom,
                    it.whenlastsold as itemwhenlastsold,
                    it.whenlastreceived as itemwhenlastreceived,
                    decode(it.cost_method, 'S','Standard','A','Average','F','FIFO',	'L','LIFO','O','Lot','#','Serial#', NULL) cost_method,
                    it.upc,
                    it.itemtype
				FROM
                    icitem it, icprodline pl, icuomgrp uomgrp, icuom uom
				WHERE
                    {$this->prodlineChildMapQry}
				    {$this->filterItemorUPC}
				    it.itemtype in ('I','SK')
                    AND it.producttype != 'PROFSERVICE'
                    AND pl.productlineid (+) = it.productlinekey
                    AND uom.grpkey (+) = uomgrp.record#
                    AND uomgrp.record# (+) = it.uomgrpkey
                    AND uom.isbase (+) = 'T'
                    AND it.cny# = ?
                    AND uomgrp.cny# (+) = ?
                    AND uom.cny# (+)= ?
                    AND pl.cny# (+) = ?
				ORDER BY  itemid",
            'ARGTYPES' => $this->itemargtypes
        );
        $items = $this->_QM->DoCustomQuery($itemcode, $this->itemargs, true);
        $this->_items = ( $items ?: array() );
    }
    
    /**
     * function to fetch Item Warehouse Information
     */
    function doQueryItemWarehouses()
    {
        array_push($this->itemwhseargs, $this->fromwarehouseid, $this->towarehouseid);
        array_push($this->itemwhseargtypes, 'text', 'text', 'integer', 'integer', 'integer', 'integer');

        $itemwhsecode = array(
            'QUERY'=> "
                SELECT
                    rownum,
                    itw.itemkey itemid,
                    itw.warehousekey warehouseid,
                    itw.warehousekey||' - '||wh.name warehouse,
                    itw.whenlastsold as whsewhenlastsold,
                    itw.whenlastreceived as whsewhenlastreceived,
                    itw.last_cost,
                    pl.productlineid,
                    it.locationkey ITOWNERLOC,
                    wh.locationkey WHOWNERLOC, it.upc
				FROM
				    icitemwhse itw, icwarehouse wh, icitem it, icprodline pl
				WHERE
				    {$this->prodlineChildMapQry}
                    ({$this->filterItemorUPC} it.itemtype IN ('I','SK') AND itw.warehousekey BETWEEN ? AND ?)
                    AND wh.location_no = itw.warehousekey
                    AND it.itemid = itw.itemkey
                    AND it.producttype != 'PROFSERVICE'
                    AND pl.productlineid (+) = it.productlinekey
                    AND itw.cny# = ?
                    AND wh.cny# = ?
                    AND it.cny# = ?
                    AND pl.cny# (+) = ?
                    {$this->whLocFilter}
                    {$this->whFilter}
				ORDER BY  warehouseid",
            'ARGTYPES' => $this->itemwhseargtypes
        );
        $itemswhse = $this->_QM->DoCustomQuery($itemwhsecode, $this->itemwhseargs, true);

        $this->_itemswhse = $itemswhse;
    }

    /**
     * function doQueryStdAvgItems()
     *
     * @return array
     */
    function doQueryFromItemHist()
    {
        $whseQry = ($this->whseQry != '') ? 'AND iac.whsekey IN '.$this->whseQry : '';
        $whSelect = '';
        $whFilter = '';
        if ($this->hideinactivewh == 'true') {
            $whSelect = ", icwarehouse icwh ";
            $whFilter = " and icwh.cny# = iac.cny# and icwh.warehouseid = iac.whsekey and icwh.status  = 'T' ";
        }
        $itemClause = '';
        if((isset($this->filterItemorUPC)  && $this->filterItemorUPC !='')||
           (isset($this->prodlineChildMapQry) && $this->prodlineChildMapQry != '' )){
            $itemFilter = isl_preg_replace($this->filterItemorUPC, ' :4 ', ' ? ');
            $itemFilter = isl_preg_replace($itemFilter, ' :5 ', ' ? ');
            $itemClause = " AND exists (
                                SELECT
                                    1
                                FROM
                                    icitem it,
                                    icprodline pl
                                WHERE
                                    {$this->prodlineChildMapQry}
                                    {$itemFilter}
                                    it.cny#= iac.cny#
                                    and it.itemid = iac.itemkey
                                    AND it.producttype != 'PROFSERVICE'
                                    AND pl.productlineid (+) =   it.productlinekey
                                    AND pl.cny# (+)          =   it.cny#
                            )";
        }

        $qtyonhand    = 'iac.qtyonhand';
        $qtyZeroCheck = "AND $qtyonhand != 0";
        if ($this->showqtywithvalue == 'true') {
            $qtyonhand = 'iac.qtywithvalue';
        }
        if (($this->shownegvalues == 'true') || ($this->showzeroquantities == 'true')) {
            $qtyZeroCheck = ''; // allow zero quantity
        }
        $itmhistcost = array();
        $qry = "with inv_val as 
                          (select  /*+ materialize */  whsekey, itemkey, max(ason) ason from itmhistcost 
                          where cny#  =  :1 and whsekey BETWEEN :2 and :3  
                          and itemkey between :4 and :5 and ason <= TO_DATE (:6, 'mm/dd/yyyy') 
                          -- and COSTMETHOD IN ('S','A', 'L', 'F')
                          group by whsekey, itemkey)
                     select iac.whsekey warehousekey, iac.itemkey itemid,
                            iac.cost cost,
                            $qtyonhand AS quantity,
                            iac.extendedcost
                        FROM
                            itmhistcost iac, inv_val $whSelect
                        WHERE
                            iac.cny#= :1
                            AND iac.whsekey = inv_val.whsekey       
                            AND iac.itemkey = inv_val.itemkey
                            AND iac.ason = inv_val.ason       
                            $qtyZeroCheck                   
                            $itemClause
                            {$whseQry}
                            $whFilter";

        $itmhistcost[0] = $qry;
        array_push($itmhistcost,$this->cny, $this->fromwarehouseid ,$this->towarehouseid,$this->fromitemid,$this->toitemid, $this->dt2);

        return QueryResult($itmhistcost);

    }

    
    /**
     * @param string $filterdept        Filter Department Query String
     * @param string $filterlocation    Filter Location Query String
     * @param string $whseQry           Filter Using Warehouse ownership location Query String
     *
     * @return bool|string[][]
     */
    function doQueryForDetailMode($filterdept, $filterlocation, $whseQry)
    {
        /** @noinspection PhpUndefinedVariableInspection */
        $deWarehouse = '';
        if ($this->fromwarehouseid && $this->towarehouseid) {
            $deWarehouse = ' and docentry.warehousekey between ? and ?';
        }
        $whSelect= '';
        $whFilter= '';
        if ($this->hideinactivewh == 'true') {
            $whSelect = ", icwarehouse icwh ";
            $whFilter = "  and icwh.cny# = docentry.cny# and icwh.warehouseid = docentry.WAREHOUSEKEY and icwh.status  = 'T' ";
        }

        $detailModecode = array(
            'QUERY' =>
                "SELECT
						doccost.itemkey AS itemid,
						doccost.whsekey warehousekey,
						dochdr.melocationkey DOCOWNERLOC,
						doccost.quantity - nvl(doccostchildren.quantity,0) as qtyleft,
						dochdr.docno,
						dochdr.whencreated,
						dochdr.docparkey,
						docentry.quantity as originalquantity,
						docentry.lineno,
						dochdr.docid as transdescription,
						doccost.cost,
						(doccost.quantity - nvl(doccostchildren.quantity,0)) * doccost.unitcost value,
						doccost.unitcost as costeach,
						doccost.sale_pur_trans as transactionmodule
					FROM
						docentrycost doccost,
						docentrymst docentry ,
						dochdrmst dochdr, 
						(select itemkey, whsekey, docentrycostkey, sum(quantity) quantity
						from
						(select itemkey, whsekey, docentrycostkey, quantity 
						from docentrycost where cny# = ? and datein <= to_date(?,'mm/dd/yyyy')
						AND  in_out = 'O' AND adjdocentrycostkey IS NULL						
						union all 
						select itemkey, whsekey, docentrycostkey, quantity 
						from docentrycostkits where cny# = ? and datein <= to_date(?,'mm/dd/yyyy')
						AND  in_out = 'O')
						group by itemkey, whsekey, docentrycostkey) doccostchildren
						$whSelect
                    WHERE
						doccost.affects_inventory IN ('V','QV')
						AND docentry.dochdrkey = dochdr.record#
						AND doccost.docentrykey = docentry.RECORD#
						AND dochdr.whencreated <= to_date(?,'mm/dd/yyyy')
						AND doccost.in_out = 'I'
						AND dochdr.state NOT IN ('I','S','A', 'X', 'R')
						AND doccost.cny# = docentry.cny#
						AND docentry.cny# = dochdr.cny#
						AND doccost.adjdocentrycostkey IS NULL
						and doccostchildren.itemkey (+)= doccost.itemkey
						and doccostchildren.whsekey (+)= doccost.whsekey
						and doccostchildren.docentrycostkey (+)= doccost.record# 
						{$deWarehouse} 
						AND doccost.itemkey IN (
                                SELECT
                                    it.itemid
                                FROM
                                    icitem it,
                                    icprodline pl
                                WHERE
                                    {$this->prodlineChildMapQry}
                                    {$this->filterItemorUPC}
                                    it.cny#= ?
                                    AND it.itemtype in  ('I', 'SK')
                                    AND it.producttype != 'PROFSERVICE'
                                    AND it.cost_method IN ('S','A', 'L', 'F')
                                    AND pl.productlineid (+) =   it.productlinekey
                                    AND pl.cny# (+)          =   it.cny#
                            )                           
                        AND dochdr.cny# = ? 
                        AND doccost.quantity - nvl(doccostchildren.quantity,0) != 0
						{$filterdept}
                        {$filterlocation}
                        {$whseQry}
                        {$whFilter}
                    ORDER BY
                        docentry.whencreated ASC",
            'ARGTYPES' => $this->detailmodeargtypes
        );


        $this->detailModeRecs = $this->_QM->DoCustomQuery($detailModecode, $this->detailmodeargs, true);
        return true;
    }

    /**
     * function setDocParInfo()
     */
    function setDocParInfo()
    {
        $docParInfo = array();

        $docParCode = array(
            'QUERY'=> "SELECT
                    docpar.record#,
                    docpar.updinv,
                    docpar.docclass
				FROM
                    docpar docpar
				WHERE
                    docpar.cny# = ?
            ",
            'ARGTYPES' => array('integer')
        );
        $docPars = $this->_QM->DoCustomQuery($docParCode, array($this->cny), true);

        foreach ($docPars as $docPar) {
            $docParInfo[$docPar['RECORD#']] = $docPar;
        }

        $this->docParInfo = $docParInfo;
    }

    /**
     * function getDocParInfo($docParKey, &$updInv, &$docClass)
     *
     * @param int       $docParKey  Doc Par Key
     * @param string    &$updInv    Update Inventory Flag passed by Reference
     * @param string    &$docClass  Document Class passed by Reference
     */
    function getDocParInfo($docParKey, &$updInv, &$docClass)
    {
        $docParInfo = $this->docParInfo[$docParKey];
        $updInv = $docParInfo['UPDINV'];
        $docClass = $docParInfo['DOCCLASS'];
    }

    /**
     *
     * Function to generate the location filter string for use
     *
     * @param  array $params
     * @param string $tableName
     * @param string $locationField
     *
     * @return string
     */
    private function _getLocationFilter($params, $tableName='docentry', $locationField = 'locationkey') {

        $filterlocation = "";

        if ($this->locations === null) {
            $this->locations = [];
            if ($params['LOCATION'] != '' && count($params['LOCATION'])) {
                $_userid = Globals::$g->_userid;
                $locs = array();

                foreach ($params['LOCATION'] as $loc) {
                    [$loc_no] = explode("--", $loc);
                    GetRecordNo($_userid, 'location', $loc_no, $locrec);

                    if (!isset($locrec) || $locrec == '') {
                        global $gErr;
                        $gErr->addIAError('INV-0501', __FILE__ . " : " . __LINE__,
                            "Location ID '$loc_no' is invalid.", ['LOC_NO' => $loc_no]);
                        return false;
                    }

                    $locs[] = $locrec;
                }
                $this->fetchLocationKeys($params, $locs);
            }
        }
        if (!empty ($this->locations)) {
            $filterlocation = PrepINClauseStmt('', $this->locations, " AND {$tableName}.{$locationField}");
        }
        return $filterlocation;

    }

    /**
     * @param array $params
     * @param array $locs
     *
     * @return array|bool
     */
    protected function fetchLocationKeys($params, $locs)
    {
        if (empty($locs)) {
            return false;
        }
        if ( !empty($this->locations) ) {
            return $this->locations;
        }
        $loc_string = implode(', ', $locs);

        $starts_with = null;
        // Use the FilterLocations control to get the users selection to get the location list to filter by
        if ($params['FILTERTRANSACTIONS'] == 'CHILDREN') {
            $starts_with = 'PARENTKEY';
        }
        else if($params['FILTERTRANSACTIONS'] != 'SELF') {
            $starts_with = 'RECORD#';
        }

        if ( isset($starts_with) ) {
            $loc_filter_query = [
                'QUERY' => "SELECT  distinct(RECORD#)
                    FROM LOCATIONMST
                    WHERE  CNY#=? start with {$starts_with} in ({$loc_string}) and CNY#=? connect by prior RECORD#=PARENTKEY and CNY#=? ",
                'ARGTYPES' => ['integer','integer','integer']
            ];
            $loc_query_result = $this->_QM->DoCustomQuery($loc_filter_query, array($this->cny, $this->cny, $this->cny), true);

            foreach ($loc_query_result as $loc) {
                $this->locations[] = $loc['RECORD#'];
            }
        } else {
            $this->locations = $locs;
        }
        return true;
    }

    /**
     * @param array $params
     *
     * @return string
     */

    function GenerateJavascript($params)
    {
        parent::GenerateJavascript($params);

        return "
			function drilldown(opid, rec, ownerloc) {

				if ( !rec ) { return ; }

				var URL;

				if( opid ){
					URL = 'editor.phtml?.op=' + opid + '&.do=view' + '&.r=' + encodeURIComponent(rec) ;
				}
				else{
					URL = '#';
				}

				DoDrill(URL, 'false', ownerloc);
			}
		";
    }
}

/**
 ***********************************************************************************************
 * Support for 'invvaluation_stdxml.xsl' and 'invvaluation_custxml.xsl':
 *
 *      THIS CODE MIMICS THE XSL INSIDE invvaluation_stdxml.xsl and invvaluation_custxml.xsl,
 *      SO IF YOU CHANGE ONE, CHANGE BOTH!!
 *      (The PHP transformation is faster than the XSL transformation, hence the duplication here.)
 *
 *		This gets called by xsl_interface.cls
 *
 ***********************************************************************************************
 */

/**
 * This transformation handles the initial, asynchronous CSV/Excel report formats
 *
 * @param mixed    $xslpath       can't determine the type; unused in the function...
 * @param DOMXPath $xmlpath
 * @param string[] &$replaceList
 */
function invvaluation_custxml_ProcessItems(/** @noinspection PhpUnusedParameterInspection */ $xslpath, $xmlpath, &$replaceList)
{
    // Transform source XML to PHP
    $reportPHP = transformXMLToPHP($xmlpath, InvValuationReport::CUSTPHPITEMS);
    // Transform PHP to report XML format
    $rtn = transformPHPToCustXML($reportPHP);
    // This text gets replaced in the finished XML with the contents of $rtn
    $replaceList['REPLACE_invvaluation_custxml_HERE'] = $rtn;
}

/**
 * This transformation handles all report formats not transformed by invvaluation_custxml_ProcessItems()
 *
 * @param mixed    $xslpath       can't determine the type; unused in the function...
 * @param DOMXPath $xmlpath
 * @param string[] &$replaceList
 */
function invvaluation_stdxml_ProcessItems(/** @noinspection PhpUnusedParameterInspection */ $xslpath, $xmlpath, &$replaceList)
{
    // Transform source XML to PHP
    $reportPHP = transformXMLToPHP($xmlpath, InvValuationReport::STDPHPITEMS);
    // Transform PHP to report XML format
    $rtn = transformPHPToStdXML($reportPHP);
    // This text gets replaced in the finished XML with the contents of $rtn
    $replaceList['REPLACE_invvaluation_stdxml_HERE'] = $rtn;
}

/**
 * Convert the source XML from DOM objects to PHP arrays. Along with
 * the PHP representation of the report itself, capture some metadata
 * which influence parts of the subsequent transformation back to the
 * desired XML format.
 *
 * @param DOMXPath $xmlpath
 *
 * @param string   $itemType
 *
 * @return array
 */
function transformXMLToPHP($xmlpath, $itemType)
{
    $reportPHP = array();
    $reportPHP['META'] = getReportMetadata($xmlpath, $itemType);

    $phpItems = array();
    $items = $xmlpath->query("//report/" . $reportPHP['META']['ITEMS']);
    if ($items != false) {
        transformItemsXMLToPHP($items, $phpItems, $reportPHP['META']);
    }
    $reportPHP['ITEMS'] = $phpItems;

    return $reportPHP;
}

/**
 * Extract report attributes that modify the way it's transformed/rendered from the raw data.
 * Specifically, we need to remember several things:
 * (i) whether this company is mult-currency, with multiple base currencies
 * (ii) whether it's "narrow format" (i.e., report format is PDF or RTF)
 * (iii) whether to display the "ITEMID" or "UPC" item identifier
 * (iv) report summary level ('Detail' vs 'Item Summary' vs 'Warehouse Summary')
 * (v) keys to use in traversing DOM nodes for the various objects
 * (vi) set up the text columns which require HTML escaping (not a report attribute per se)
 *
 * @param DOMXPath $xmlpath  Report XML
 *
 * @param string   $itemType Type of template to follow
 *
 * @return array Metadata of interest
 */
function getReportMetadata($xmlpath, $itemType) {
    $reportMeta = [];
    $reportMeta['ISMCMESUBSCR'] = $xmlpath->query("//report/@ISMCMESUBSCR")->item(0)->nodeValue;
    $reportFormat = $xmlpath->query("//report/@report_format")->item(0)->nodeValue;
    $reportMeta['NARROW_FORMAT'] = $reportFormat == '_pdf' || $reportFormat == '_rtf';
    $reportMeta['ITEMCN'] = $xmlpath->query("//report/@term_Item")->item(0)->nodeValue == 'UPC' ?
        'UPC' : 'ITEMID';
    $reportMeta['SUMMARY'] = $xmlpath->query("//report/@summary")->item(0)->nodeValue;

    /*
     * Different keys used for different report types, trying to sidestep template matches,
     * to avoid XSL tests and conditional XML emission.
     */
    if ($itemType == InvValuationReport::STDPHPITEMS) {
        $reportMeta['ITEMS'] = InvValuationReport::STDPHPITEMS;
        $reportMeta['WAREHOUSE'] = InvValuationReport::STDPHPWAREHOUSE;
        $reportMeta['TRANSACTION'] = InvValuationReport::STDPHPTRANSACTION;
    } else if ($itemType == InvValuationReport::CUSTPHPITEMS) {
        $reportMeta['ITEMS'] = InvValuationReport::CUSTPHPITEMS;
        $reportMeta['WAREHOUSE'] = InvValuationReport::CUSTPHPWAREHOUSE;
        $reportMeta['TRANSACTION'] = InvValuationReport::CUSTPHPTRANSACTION;
    }

    // Escape text attributes in case they have special characters (no dates or numbers)
    $reportMeta['ITEMESCAPE'] = ['ITEMID', 'ITEM', 'UPC', 'DESCRIPTION', 'COST_METHOD', 'PRODUCTLINE', 'UOM'];
    $reportMeta['WAREHOUSEESCAPE'] = ['NAME'];
    $reportMeta['TRANSACTIONESCAPE'] = ['DOCNO', 'TRANSDESCRIPTION'];
    return $reportMeta;
}

/**
 * Convert the list of item DOM objects, if any, to corresponding
 * array entries. Populate the warehouse and transaction array
 * entries for each item along the way.
 *
 * @param DOMNodeList|false $items      Item nodes, if any, to convert
 *
 * @param string[]          $phpArray   The converted PHP items array
 *
 * @param array $reportMeta Report metadata
 */
function transformItemsXMLToPHP($items, &$phpArray, $reportMeta)
{
    foreach($items as $item) {
        /** @var DOMElement $item */
        if ($item->hasAttributes()) {
            $itemAttributes = $item->attributes;
            $attributeCount = $itemAttributes->length;
            // Collect this Item's attributes
            $itemPHPArray = array();
            for ( $itemIdx = 0; $itemIdx < $attributeCount; $itemIdx++ ) {
                $one = $itemAttributes->item($itemIdx);
                $itemPHPArray[$one->nodeName] = $one->nodeValue;
            }
            foreach ($reportMeta['ITEMESCAPE'] as $attributeToEscape) {
                $itemPHPArray[$attributeToEscape] = isl_htmlspecialchars($itemPHPArray[$attributeToEscape]);
            }
            $itemID = $itemPHPArray['ITEMID'];
            // Use this for reporting later to avoid repeated tests for ITEMID/UPC
            $itemCN = $itemPHPArray[$reportMeta['ITEMCN']];
            $itemPHPArray['ITEMCN'] = $itemCN;
            $phpArray[$itemID] = $itemPHPArray;
            if ($item->hasChildNodes()) {
                // We should find warehouses here
                transformWarehouseXMLToPHP($itemID, $phpArray, $reportMeta, $item->childNodes);
            }
        }
    }
}

/**
 * Convert the list of warehouse DOM objects, if any, to corresponding
 * array entries. Populate the transaction array entries for each
 * warehouse along the way.
 *
 * @param string      $itemID
 * @param array &     $phpArray
 * @param array       $reportMeta
 * @param DOMNodeList $childNodes
 */
function transformWarehouseXMLToPHP($itemID, &$phpArray, $reportMeta, $childNodes)
{
    foreach ($childNodes as $childNode) {
        /** @var DOMNode $childNode */
        $childNodeName = $childNode->nodeName;
        if ($childNodeName == $reportMeta['WAREHOUSE']) {
            $warehousePHPArray = [];
            if ( $childNode->hasAttributes() ) {
                $warehouseAttributes = $childNode->attributes;
                $warehouseAttributeCount = $warehouseAttributes->length;
                for ( $whIdx = 0; $whIdx < $warehouseAttributeCount; $whIdx++ ) {
                    $one = $warehouseAttributes->item($whIdx);
                    $warehousePHPArray[$one->nodeName] = $one->nodeValue;
                }
                foreach ( $reportMeta['WAREHOUSEESCAPE'] as $attributeToEscape ) {
                    $warehousePHPArray[$attributeToEscape] =
                        isl_htmlspecialchars($warehousePHPArray[$attributeToEscape]);
                }
                $phpArray[$itemID]['WAREHOUSE'][$warehousePHPArray['NAME']] = $warehousePHPArray;
            }
            if ( $childNode->hasChildNodes() ) {
                // We should find transactions here
                transformTransactionXMLToPHP($itemID, $warehousePHPArray['NAME'], $phpArray, $reportMeta,
                                             $childNode->childNodes);
            }
        }
    }
}

/**
 * Convert the list of transaction DOM objects, if any, to corresponding
 * array entries.
 *
 * @param string      $itemID
 * @param string      $warehouseName
 * @param array &     $phpArray
 * @param array       $reportMeta
 * @param DOMNodeList $childNodes
 */
function transformTransactionXMLToPHP($itemID, $warehouseName, &$phpArray, $reportMeta, $childNodes)
{
    foreach ($childNodes as $childNode) {
        /** @var DOMNode $childNode */
        $childNodeName = $childNode->nodeName;
        if ($childNodeName == $reportMeta['TRANSACTION']) {
            if ($childNode->hasAttributes()) {
                $transactionAttributes = $childNode->attributes;
                $transactionAttributeCount = $transactionAttributes->length;
                $transactionPHPArray = array();
                for ( $txnIdx = 0; $txnIdx < $transactionAttributeCount; $txnIdx++ ) {
                    $one = $transactionAttributes->item($txnIdx);
                    $transactionPHPArray[$one->nodeName] = $one->nodeValue;
                }
                foreach ( $reportMeta['TRANSACTIONESCAPE'] as $attributeToEscape ) {
                    $transactionPHPArray[$attributeToEscape] =
                        isl_htmlspecialchars($transactionPHPArray[$attributeToEscape]);
                }
                $phpArray[$itemID]['WAREHOUSE'][$warehouseName]['TRANSACTION'][] = $transactionPHPArray;
            }
        }
    }
}

/**
 * Render XML per the "custom" template, i.e., when either of CSV or Excel is
 * initially chosen for an asynchronous report.
 *
 * @param array &$reportPHP PHP report representation
 *
 * @return string           The transformed XML report
 */
function transformPHPToCustXML(&$reportPHP)
{
    $rtn = "";
    foreach($reportPHP['ITEMS'] ?? [] as $phpItem) {
        $rtn .= transformItemPHPToCustXML($phpItem, $reportPHP['META']);
    }
    return $rtn;
}

/**
 * Render XML per the "standard" template, i.e., all cases other than when either
 * of CSV or Excel is initially chosen for an asynchronous report (including all
 * synchronous report formats).
 *
 * @param array &$reportPHP PHP report representation
 *
 * @return string           The transformed XML report
 */
function transformPHPToStdXML(&$reportPHP)
{
    $rtn = "";
    foreach($reportPHP['ITEMS'] ?? [] as $phpItem) {
        $rtn .= transformItemPHPToStdXML($phpItem, $reportPHP['META']);
    }
    return $rtn;
}

/**
 * Transform the Item PHP representation to the report's output XML format.
 * Each item may have warehouse details, and they in turn may have
 * transaction detail. So, we fill those in here in order, per item,
 * as applicable.
 *
 * @param array $phpItem    PHP item representation
 *
 * @param array $reportMeta Report metadata
 *
 * @return string           Transformed XML item
 */
function transformItemPHPToCustXML($phpItem, $reportMeta)
{
    $xmlItem = '';
    $xmlItemPrefix = '
    <row s="12">' .
        '<col id="0" s="19">' . $phpItem['ITEMCN'] . '</col>' .
        '<col id="0" s="19">' . $phpItem['DESCRIPTION'] . '</col>' .
        '<col id="0" s="19">' . $phpItem['COST_METHOD'] . '</col>' .
        '<col id="0" s="19">' . $phpItem['PRODUCTLINE'] . '</col>' .
        '<col id="0" s="19">' . $phpItem['UOM'] . '</col>';
    $xmlItem .= transformWarehousPHPToCustXML($phpItem, $xmlItemPrefix, $reportMeta);
    return $xmlItem;
}

/**
 * Transform the PHP representation to the report's output XML format.
 * Each item may have warehouse details, and they in turn may have
 * transaction detail. So, we fill those in here in order, per item,
 * as applicable.
 *
 * @param array $phpItem    PHP item representation
 *
 * @param array $reportMeta Report metadata
 *
 * @return string           Transformed XML item
 */
function transformItemPHPToStdXML($phpItem, $reportMeta)
{
    $colSpan = '';
    $padColumns = '';
    if ($reportMeta['NARROW_FORMAT']) {
        $colSpan = ' colspan="6" ';
    } else {
        $padColumns = '<col id="0" s="24"/><col id="0" s="24"/><col id="0" s="24"/><col id="0" s="24"/><col id="0" s="24"/>';
    }
    // First, take care of the top line item row
    $xmlItem = '';
    $xmlItem .= '
    <row s="">' .
                '<col id="0" s="20" href="'. $phpItem['HREF'] . '">' . $phpItem['ITEMCN'] . '</col>' .
                '<col id="0" s="24">' . $phpItem['COST_METHOD'] . '</col>' .
                '<col id="0" s="24"' . $colSpan . '>' . $phpItem['PRODUCTLINE'] . '</col>' . $padColumns .
                '<col id="0" s="25"/><col id="0" s="25"/><col id="0" s="25"/><col id="0" s="25"/><col id="0" s="25"/><col id="0" s="25"/></row>';
    // Next, append any warehouse rows associated with this item (transactions will be included here, if any)
    $xmlItem .= transformWarehousPHPToStdXML($phpItem, $reportMeta);
    if ($reportMeta['ISMCMESUBSCR'] == 'false') {
        $colSpan = '';
        $padColumns = '';
        if ($reportMeta['NARROW_FORMAT']) {
            $colSpan = ' colspan="3" ';
        } else {
            $padColumns = '<col id="0" s="23"/><col id="0" s="23"/>';
        }
        // Then, append the summary/aggregate line for this item
        $xmlItem .= '
    <row s="">' .
                 '<col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/>' .
                 '<col id="0" s="23" ' . $colSpan . 'href="' . $phpItem['HREF'] . '">' .
                    $phpItem['ITEMCN'] . ' '. 'IA.SUMMARY'. '</col>' . $padColumns .
                    '<col id="0" s="71">' . $phpItem['DLA'] . '</col>' .
                 '<col id="0" s="62">' . $phpItem['LASTCOST'] . '</col>' .
                 '<col id="0" s="62">' . $phpItem['QUANTITY'] . '</col>' .
                 '<col id="0" s="62">' . $phpItem['COSTEACH'] . '</col>' .
                 '<col id="0" s="30">' . $phpItem['VALUE'] . '</col>' .
                 '</row>';
    }
    // Finally, add in the trailing row
    $xmlItem .= '
    <row s=""><col id="0" s="19"></col></row>';
    return $xmlItem;
}

/**
 * Transform the PHP representation to the report's output XML format.
 * Iterate over and transform all warehouses for the specified item.
 * Each warehouse may have transaction details. We fill those in here in
 * order, per warehouse, as applicable. In this format, item details are
 * prepended to the warehouse lines.
 *
 * @param array  $phpItem      PHP item representation
 *
 * @param string $xmlIemPrefix Item prefix
 *
 * @param array  $reportMeta   Report metadata
 *
 * @return string The output XML representation of warehouses and transactions
 */
function transformWarehousPHPToCustXML($phpItem, $xmlIemPrefix, $reportMeta)
{
    $xmlWarehouses = '';
    foreach ($phpItem['WAREHOUSE'] ?? [] as $name => $warehouse) {
        $xmlWarehousePrefix = $xmlIemPrefix . '<col id="0" s="19">' . $name . '</col>';
        $xmlWarehouses .= transformTransactionPHPToCustXML($warehouse['TRANSACTION'], $xmlWarehousePrefix);
        $xmlWarehouses .= $xmlWarehousePrefix;
        if ($reportMeta['SUMMARY'] == 'Detail') {
            $xmlWarehouses .= '<col id="0" s="19"/><col id="0" s="44"/><col id="0" s="22"/><col id="0" s="22"/><col id="0" s="34"/>';
        }
        $xmlWarehouses .= '<col id="0" s="21">' . $warehouse['DLA'] . '</col>' .
                '<col id="0" s="22">' . $warehouse['LASTCOST'] . '</col>' .
                '<col id="0" s="22">' . $warehouse['QUANTITY'] . '</col>' .
                '<col id="0" s="34">' . $warehouse['COSTEACH'] . '</col>' .
                '<col id="0" s="34">' . $warehouse['VALUE'] . '</col>' .
            '</row>';
    }
    return $xmlWarehouses;
}

/**
 * Transform the PHP representation to the report's output XML format.
 * Iterate over and transform all warehouses for the specified item.
 * Each warehouse may have transaction details. We fill those in here in
 * order, per warehouse, as applicable.
 *
 * @param array $phpItem    PHP item representation
 *
 * @param array $reportMeta Report metadata
 *
 * @return string The output XML representation of warehouses and transactions
 */
function transformWarehousPHPToStdXML($phpItem, $reportMeta)
{
    $firstRow = true;
    $xmlWarehouses = '';
    foreach ($phpItem['WAREHOUSE'] ?? [] as $name => $warehouse) {
        $hasTransactions = ($warehouse['TRANSACTION'] ?? null) != null;
        $xmlWarehouses .= '
    <row s=""><col id="0" s="24"/>';
        if ($firstRow) {
            // Only include itemID and UOM with the first warehouse
            $xmlWarehouses .= '<col id="0" s="24">' . $phpItem['DESCRIPTION'] . '</col>' .
                '<col id="0" s="24">' . $phpItem['UOM'] . '</col>';
        } else {
            $xmlWarehouses .= '<col id="0" s="24"/><col id="0" s="24"/>';
        }
        $nameColspan = '';
        $nameColEnd = '</col>';
        $padColumns = '';
        if ($reportMeta['NARROW_FORMAT']) {
            $nameColspan = ' colspan="6" ';
        } else {
            $padColumns = '<col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/>';
        }
        $xmlWarehouses .= '<col id="0" s="19"' . $nameColspan . '>' . $name . $nameColEnd . $padColumns;

        /*
         * A warehouse with transactions will include a separate "bottom line" summary,
         * whereas one without transactions will include the summary in its single line.
         */
        if ($hasTransactions) {
            // Empty columns here, separate warehouse summary following transaction lines
            $xmlWarehouses .= '<col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/>';
        } else {
            // No transaction lines, so combine summary columns here
            $xmlWarehouses .= '<col id="0" s="21">' . $warehouse['DLA'] . '</col>' .
                '<col id="0" s="22">' . $warehouse['LASTCOST'] . '</col>' .
                '<col id="0" s="22">' . $warehouse['QUANTITY'] . '</col>' .
                '<col id="0" s="22">' . $warehouse['COSTEACH'] . '</col>' .
                '<col id="0" s="34">' . $warehouse['VALUE'] . '</col>';
        }
        $xmlWarehouses .= '</row>';
        $xmlWarehouses .= transformTransactionPHPToStdXML($warehouse['TRANSACTION'] ?? null);
        if ($hasTransactions) {
            // Warehouse summary line
            $xmlWarehouses .= '
    <row s=""><col id="0" s="24"/><col id="0" s="24"/><col id="0" s="24"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/><col id="0" s="19"/>' .
                '<col id="0" s="21">' . $warehouse['DLA'] . '</col>' .
                '<col id="0" s="22">' . $warehouse['LASTCOST'] . '</col>' .
                '<col id="0" s="22">' . $warehouse['QUANTITY'] . '</col>' .
                '<col id="0" s="22">' . $warehouse['COSTEACH'] . '</col>' .
                '<col id="0" s="34">' . $warehouse['VALUE'] . '</col>' .
            '</row>';
        }
        $firstRow = false;
    }
    return $xmlWarehouses;
}

/**
 * Transform transactions. In this format, warehouse details are prepended
 * to the transaction lines.
 *
 * @param array  $transactions       List of transactions to transform
 *
 * @param string $xmlWarehousePrefix Prefix for each transaction line
 *
 * @return string
 */
function transformTransactionPHPToCustXML($transactions, $xmlWarehousePrefix)
{
    $xmlTransactions = '';
    foreach ($transactions ?? [] as $transaction) {
        $xmlTransactions .= $xmlWarehousePrefix;
        $xmlTransactions .= '<col id="0" s="19">' . $transaction['TRANSDESCRIPTION'] . '</col>' .
            '<col id="0" s="21">' . $transaction['DATE'] . '</col>' .
            '<col id="0" s="22">' . $transaction['QUANTITY'] . '</col>' .
            '<col id="0" s="22">' . $transaction['COSTEACH'] . '</col>' .
            '<col id="0" s="22">' . $transaction['VALUE'] . '</col>' .
        '</row>';
    }
    return $xmlTransactions;
}

/**
 * Transform transactions.
 *
 * @param array $transactions List of transactions to transform
 *
 * @return string The output XML representation of transactions
 */
function transformTransactionPHPToStdXML($transactions)
{
    $xmlTransactions = '';
    foreach ($transactions ?? [] as $transaction) {
        $xmlTransactions .= '
    <row s=""><col id="0" s="24"/><col id="0" s="24"/><col id="0" s="24"/><col id="0" s="22"/>' .
            '<col id="0" s="19" href="'. $transaction['HREF'] . '">' . $transaction['TRANSDESCRIPTION'] . '</col>' .
            '<col id="0" s="21">'. $transaction['DATE'] . '</col>' .
            '<col id="0" s="22">'. $transaction['QUANTITY'] . '</col>' .
            '<col id="0" s="22">'. $transaction['COSTEACH'] . '</col>' .
            '<col id="0" s="34">'. $transaction['VALUE'] . '</col>' .
            '<col id="0" s="24"/><col id="0" s="24"/><col id="0" s="24"/><col id="0" s="24"/><col id="0" s="24"/></row>';
    }
    return $xmlTransactions;
}
