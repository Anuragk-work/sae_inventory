<?php

/**
 * FILE: ReconcileReportHelper.cls
 * AUTHOR: Roger Collins
 * DESCRIPTION: Reconcile report to reconcile item activity, valuation, and the GL
 *      based on a design by Tracy Tremblay
 *
 * (C) 2019, Sage Intacct Corporation, All Rights Reserved
 *
 * This document contains trade secret data that belongs to Sage Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Sage Intacct Corporation.
 */

// NOTE: This is currently part of a CS Tool,
class ReconcileReportHelper
{
    // report types
    const       VALUATION_VS_ITEM_ACTIVITY  = 'valuationVsItemActivity';
    const       QOH                         = 'QOH';
    const       ALL_DETAILS                 = 'detail';


    const       SKIT_PART = " (Part)";

    /** @var string[]|null  $itemClause        the from and to items as an array, or an empty array */
    private     $itemClause = null;

    /** @var string[]|null  $warehouseClause   the from and to warehouses as an array, or an empty array */
    private     $warehouseClause = null;

    /** @var string|null   $startDate         the report start date  */
    private     $startDate = null;

    /** @var string|null    $onOrBeforeDate    run report as of this date */
    private     $onOrBeforeDate = null;

    /** @var array $accounts                   account record# --> Account number and title */
    private     $accounts = [];

    /** @var string $notes                     Notes to add to the end of the CSV file */
    private     $notes = '';

    /** @var string $reportType                kind of report desired */
    private     $reportType = self::ALL_DETAILS;


    /** @var string[] $detailFields            fields and their help strings, in order of appearance on the DETAIL report */
    static private $detailFields = [
            'ITEMID'                => 'Item id',
            'NAME'                  => 'Item name',
            'WAREHOUSEID'           => 'Warehouse',
            'ASON'                  => 'Txn date',
            'MODIFIED'              => 'Last modified',
            'DOCID'                 => 'Document id',
            'LINE_NUMBER'           => 'Line on txn',
            'QUANTITY'              => 'ON-HAND qty',
            'UNITCOST'              => 'In: assigned cost; Out: Valuation rpt unit cost on asof',
            'QTYLEFT'               => 'In only: quantity - sum(out quantities)',
            'ORIG_VALUE'            => 'unitcost * qty',
            'VALUELEFT'             => 'In only: orig_value - sum(out orig_value)',
            'VALUATION_UNITCOST'    => 'Valuation rpt unit cost on asof',
            'VALUATION_EODQTY'      => 'Valuation rpt qty at end-of-day (value txns only)',
            'VALUATION_EODVALUE'    => 'valuation_unitcost * valuation_eodqty',
            'VALUE_VARIANCE'        => 'valuation_eodvalue - sum(valueleft) for this item/wh',
            'CURRENT_VALUE'         => 'Current costing value',
            'GL_CR_AMT'             => 'Cr GL Post for this item/wh',
            'GL_CR_ACCT'            => 'Cr GL Account',
            'GL_CR_VAR'             => 'diff COGS entries vs GL',
            'GL_DR_AMT'             => 'Dr GL Post for this item/wh',
            'GL_DR_ACCT'            => 'Dr GL Account',
            'GL_DR_VAR'             => 'diff COGS entries vs GL',
            'COGS_DELTA'            => 'diff COGS amount vs current_value',
            'LOCATION'              => 'Location',
            'COST_METHOD'           => 'Cost method of item',
            'TRANSACTION_UOM'       => 'UOM for the line item',
            'INC_DEC'               => 'Inc or dec qty',
            'SPI'                   => 'Sale Purch Inventory',
            'UPDINV'                => 'Qty Val or Both (T)',
            'NOTES'                 => 'Notes',
        ];


    /** @var string[] $valuationVsItemActivityFields            fields and their help strings, in order of appearance on the DETAIL report */
    static private $valuationVsItemActivityFields = [
            'ON_VALUATION'          => 'Is this item on the valuation report?',
            'ITEMID'                => 'Item id',
            'NAME'                  => 'Item name',
            'WAREHOUSEID'           => 'Warehouse',
            'ASON'                  => 'In Txn date',

            // the valuation INBOUND report stuff: qty/qtyleft
            'DOCID'                 => 'Document id',
            'LAYER'                 => 'Costing layer',
            'QUANTITY'              => 'Original Qty',
            'UNITCOST'              => 'price of this inbound item',
            'VALUE'                 => 'Quantity * unitcost',

            // shared between IN and OUT (i.e. out decrements this)
            'QTYLEFT'               => 'Remaining qty after outgoing txns',

            // outgoing transactions that took away from the inbound:
            'OUT_DATE'              => 'Out Txn date',
            'OUT_DOCID'             => 'Out Document id',
            'OUT_LAYER'             => 'Costing layer',
            'OUT_QUANTITY'          => 'Original Qty',

            // extra, less used stuff
            'DAILY_Q_QOH'           => 'Summary Qty QOH for the day (shows as QOH on Valuation Report)',
            'ENTEREDDATE'           => 'Date/time actually entered',
            'LOCATION'              => 'Location',
            'COST_METHOD'           => 'Cost method of item',
            'SPI'                   => 'Sale Purch Inventory',
            'UPDINV'                => 'Qty Val or Both (T)',
            'TRANSACTION_UOM'       => 'UOM for the line item',
            'NOTES'                 => 'Notes',
        ];

    /** @var string[] $QOHFields            fields and their help strings, in order of appearance on the QOH report */
    static private $QOHFields = [
            'ITEMID'                => 'Item id',
            'NAME'                  => 'Item name',
            'WAREHOUSEID'           => 'Warehouse',
            'ASON'                  => 'In Txn date',
            'IN_OUT'                => 'IN or OUT (Purchase or Sale)',
            'TXN_Q_V'               => 'Txn: Qty Val or Both (T)',
            'LAYER_Q_V'             => 'Layer: Qty or Val or Both (QV)',

            'QUANTITY'              => 'Qty on TXN',
            'Q_QTY'                 => 'Q Qty',
            'V_QTY'                 => 'V Qty',
            'QTYLEFT'               => 'Remaining qty after outgoing txns',
            'IA_QTY'                => 'IA Quantity Delta',

            'DAILY_Q_QOH'           => 'Daily Qty QOH from Item History',
            'RUNNING_Q_QOH'         => 'Running Q QOH',
            'DAILY_V_QOH'           => 'Daily Value QOH from Item History',
            'RUNNING_V_QOH'         => 'Running V QOH',

            // the valuation INBOUND report stuff: qty/qtyleft
            'DOCID'                 => 'Document id',
            'LAYER'                 => 'Costing layer',

            'UNITCOST'              => 'price of this inbound item',
            'VALUE'                 => 'Quantity * unitcost',

            'ENTEREDDATE'           => 'Date/time actually entered',
            'LOCATION'              => 'Location',
            'COST_METHOD'           => 'Cost method of item',
            'SPI'                   => 'Sale Purch Inventory',
            'TRANSACTION_UOM'       => 'UOM for the line item',
            'NOTES'                 => 'Notes',

        ];



    /**
     * ReconcileReportHelper constructor.
     *
     * @param string    $fromItem           start with this item, or if empty, 'all items'
     * @param string    $toItem             end with this item, if $fromItem is specified
     * @param string    $fromWarehouse      start with this warehouse, or if empty, 'all warehouses'
     * @param string    $toWarehouse        end with this warehouse, if $fromWarehouse is specified
     * @param string    $startDate          start the report on this date; empty means 1/1/2000
     * @param string    $onOrBeforeDate     end the report on this date; empty means 'today'
     * @param string    $reportType         one of "Detail' or 'valuationVsItemDetail'
     */
    function __construct($fromItem = '', $toItem = '', $fromWarehouse = '', $toWarehouse = '', $startDate = '', $onOrBeforeDate = '', $reportType = self::ALL_DETAILS)
    {
        // save from and to
        if ($fromItem != '') {
            $this->itemClause   = [];
            list($fromItem)     = explode("--", $fromItem);
            $this->itemClause[] = $fromItem;
            if ($toItem != '') {
                list($toItem) = explode("--", $toItem);
                $this->itemClause[] = $toItem;
            } else {
                $this->itemClause[] = $fromItem;
            }
        }
        if ($fromWarehouse != '') {
            $this->warehouseClause   = [];
            list($fromWarehouse)     = explode("--", $fromWarehouse);
            $this->warehouseClause[] = $fromWarehouse;
            if ($toWarehouse != '') {
                list($toWarehouse)     = explode("--", $toWarehouse);
                $this->warehouseClause[] =  $toWarehouse;
            } else {
                $this->warehouseClause[] =  $fromWarehouse;
            }
        }
        if ($startDate != '') {
            $this->startDate = $startDate;
        }
        if ($onOrBeforeDate != '') {
            $this->onOrBeforeDate = $onOrBeforeDate;
        }
        $this->notes        = '';
        $this->reportType   = $reportType;
    }


    /**
     *      Which fields are in the actual CSV for the report?
     *
     * @return string[]             The list of fields and help, in order of their appearance on the CSV output
     */
    private function reportFields()
    {

        switch ($this->reportType) {

            case self::VALUATION_VS_ITEM_ACTIVITY:
                $rtn = self::$valuationVsItemActivityFields;
                break;

            case self::QOH:
                $rtn = self::$QOHFields;
                break;

            case self::ALL_DETAILS:
                $rtn = self::$detailFields;
                break;

            default:
                throw new Exception("Report type unknown:" . $this->reportType);
        }
        return $rtn;
    }


    /**
     *      What is the CSV friendly report name
     *
     * @return string             The name that can be put on the report.
     */
    private function reportName()
    {
        switch ($this->reportType) {

            case self::VALUATION_VS_ITEM_ACTIVITY:
                $rtn = 'Valuation Report vs Item Activity Report Version 0.2';
                break;

            case self::QOH:
                $rtn = 'Quantity On Hand comparison of tables Report version 0.1';
                break;

            case self::ALL_DETAILS:
                $rtn = 'Recomcile report Version 0.2';
                break;

            default:
                throw new Exception("Report type unknown:" . $this->reportType);
        }
        return $rtn;
    }


    /**
     *      In the constructor we may have received a from/to item, from/to warehouse, and end-date.
     *  If so, add them to any sql query in progress....
     *
     * @param array        $qry                 array query so far; [0] is the query string
     * @param string       $itemColumnName      the sql name for the item column
     * @param string       $warehouseColumnName the sql name for the warehouse column
     * @param string       $dateColumnName      the sql name of the date column, if one
     */
    private function addItemWarehouseWhereClauses(&$qry, $itemColumnName, $warehouseColumnName, $dateColumnName = '')
    {
        $count = count($qry);
        if (is_array($this->itemClause)) {
            $qry[0]      .= " AND $itemColumnName >= :$count";
            $qry[$count++] = $this->itemClause[0];
            $qry[0]     .= " AND $itemColumnName <= :$count";
            $qry[$count++] = $this->itemClause[1];
        }
        if (is_array($this->warehouseClause)) {
            $qry[0] .= " AND $warehouseColumnName >= :$count";
            $qry[$count++] = $this->warehouseClause[0];
            $qry[0] .= " AND $warehouseColumnName <= :$count";
            $qry[$count++] = $this->warehouseClause[1];
        }
        if (($this->startDate != null) && ($dateColumnName != '')) {
            $qry[0] .= " AND $dateColumnName >= to_date(:$count,'YYYY-MM-DD')";
            $qry[$count++] = $this->startDate;
        }
        if (($this->onOrBeforeDate != null) && ($dateColumnName != '')) {
            $qry[0] .= " AND $dateColumnName <= to_date(:$count,'YYYY-MM-DD')";
            $qry[$count  ] = $this->onOrBeforeDate; // no ++ because inspections will complain
        }
    }


    /**
     * fputcsv() demands a a file, addslashes() doesn't do what I want.
     *  Excel and Google Docs use "" around strings with commas, and escape " with " before it ("")
     *
     * @param bool|string $s
     *
     * @return string
     */
    private static function escapeForCSV( $s )
    {
        if (is_bool($s)) {
            $rtn = ($s ? "Yes" : "No");
        } else if (is_numeric($s)) {
            $rtn = (($s != 0) ? ($s . '') : "");
        } else {
            $rtn = str_replace('"', '""', $s);    // escape double quotes
            if ((strpos($rtn, '"') !== false) || (strpos($rtn, ',') !== false)) { // if any double quotes or commas; could check for newlines, but in practice we won't see those
                $rtn = '"' . $rtn . '"';
            }
        }
        return $rtn;
    }


    /**
     *      sort compare for uasort() below, for the 'accounts' table
     *  Note: protected not private just to help with inspections
     *
     * @param string[] $a        the left side
     * @param string[] $b        the right side
     *
     * @return int               is -1 if left < right, +1 if left > right, 0 otherwise
     */
    protected static function sortCompareForAccounts($a, $b)
    {
        if ($a['NUM'] == $b['NUM']) {
            return 0;
        }
        return ($a['NUM'] < $b['NUM']) ? -1 : 1;
    }

    /**
     *      Generate an entire report into a single string, suitible for CSV
     *
     * @return string|bool      the report as a CSV table, or false if failed
     */
    public function getReconcileReportForCSV()
    {
        $table = $this->runQueries();   // get the rows to dump to csv

        if ($table !== false) {
            // Dump the account number to title table into the notes:
            if ( ! empty($this->accounts)) {
                uasort($this->accounts, "self::sortCompareForAccounts");
                $this->notes .= "\nCOGS GL Accounts in use:\nNUMBER,COGS TXNS,NON-COGS POSTS,TITLE\n";
                foreach ($this->accounts as $account) {
                    $this->notes .= $account['NUM'] . ',' . $account['KNOWN_TOTAL'] . ',' . $account['OTHER_TOTAL'] . ',' . self::escapeForCSV($account['TITLE']) . "\n";
                }
            }

            $fieldsInThisReport =  $this->reportFields();
            $fieldsInOrder      = array_keys($fieldsInThisReport);

            // first, put out the CSV header:
            $csv = '';
            foreach ($fieldsInOrder as $field) {
                $csv .= $field . ',';
            }
            $csv .=  $this->reportName() . " run as of " . ($this->onOrBeforeDate ?? GetCurrentDate()) . "\n";

            // for each row add the fields, escaped for CSV output
            foreach ($table as $row) {
                $comma = '';
                foreach ($fieldsInOrder as $field) {
                    $csv  .= $comma;
                    $comma = ',';
                    if (isset($row[$field])) {
                        $csv  .= self::escapeForCSV( $row[$field] );
                    }
                }
                $csv .= "\n";
            }
            $csv .= "\n";

            // add help at the bottom of the columns
            $comma = '';
            foreach ($fieldsInOrder as $field) {
                $csv  .= $comma;
                $comma = ',';
                $csv  .= self::escapeForCSV( $fieldsInThisReport[$field] );
            }

            // add any notes:
            $csv .= "\n\n" . $this->notes . "\n";
        } else {
            return false;
        }
        return $csv;
    }


    /**
     *      Run the queries for the report, return the table of data ready to be displayed or exported
     *
     * @return bool|string[][]
     */
    public function runQueries()
    {
        switch ($this->reportType) {

            case self::VALUATION_VS_ITEM_ACTIVITY:
                $table = $this->runValuationVsItemActivityQueries();
                break;

            case self::QOH:
                $table = $this->runQOHQueries();
                break;

            case self::ALL_DETAILS:
                $table = $this->runDetailsQueries();
                break;

            default:
                throw new Exception("Report type unknown:" . $this->reportType);
        }
        return $table;
    }


    /**
     *      When the item/warehouse changes, emit any output (sales) records that have NO SOURCE
     *
     * @param string        $itemId                 the Item ID we want to output for
     * @param string        $warehouseId            the Warehouse ID we want to output for
     * @param int[]         $recordsWithNoSource    set of indexes into '$outbound'
     * @param string[][]    $outbound               info on the outbound records (like sales)
     * @param string[][]    $table                  This is the CSV output table
     */
    private function emitOutputWithNoInput($itemId, $warehouseId, $recordsWithNoSource, $outbound, &$table)
    {
        if (($itemId == '') || ($warehouseId == '')) {
            return; // nothing to do
        }

        $firstTime = true;
        foreach ($recordsWithNoSource as $key) {
            $outRow = $outbound[$key];
            if (($outRow['ITEMID'] == $itemId) && ($outRow['WAREHOUSEID'] == $warehouseId)) {

                // date within range?
                if (($this->startDate != null) && ($this->MyCompareDate( $outRow['DATEIN'], $this->startDate ) < 0)) {
                    continue;
                }
                if (($this->onOrBeforeDate != null) && ($this->MyCompareDate( $outRow['DATEIN'], $this->onOrBeforeDate ) > 0)) {
                    continue;
                }

                // do we need a fake input record?
                if ($firstTime) {
                    $whatToShow = [
                        'ON_VALUATION'          => '',
                        'ITEMID'                => $itemId,
                        'NAME'                  => $outRow['NAME'],
                        'WAREHOUSEID'           => $warehouseId,
                        'ASON'                  => '',
                        'DOCID'                 => 'NO SOURCE RECORD',
                        'NOTES'                 => 'These are output items like sales which have no input items like purchases',
                    ];
                    $table[] = $whatToShow;
                    $firstTime = false;
                }

                // And now output the, er, output record.....
                $whatToShow = [

                    'UNITCOST'          => $outRow['UNITCOST'],
                    'QTYLEFT'           => 0,
                    'OUT_DATE'          => $outRow['DATEIN'],
                    'OUT_DOCID'         => $outRow['DOCID'],
                    'OUT_LAYER'         => $outRow['LAYER'],
                    'OUT_QUANTITY'      => $outRow['QUANTITY'],

                    'ENTEREDDATE'       => $outRow['ENTEREDDATE'],
                    'LOCATION'          => $outRow['LOCATION'],
                    'COST_METHOD'       => $outRow['COST_METHOD'],
                    'SPI'               => $outRow['SPI'],
                    'UPDINV'            => $outRow['UPDINV'],
                    'TRANSACTION_UOM'   => $outRow['TRANSACTION_UOM'],
                    'NOTES'             => $outRow['NOTES'],
                ];
                $table[] = $whatToShow;
            }
        }
    }


    /**
     *      A couple of the reports need the same data as their source, so .....
     *
     * @param bool          $restrictByDate
     *
     * @return bool|string[][]
     */
    private function runCommonQueries($restrictByDate)
    {
        // Do some queries and index them
        $ia = $this->runItemActivityQuery($restrictByDate);
        if ($ia === false) {
            return false;
        }
        // logFL("IA:" . var_export($ia,true));

        // index the activity table.....
        $iaIndex      = [];
        $iaIndexShort = [];
        foreach ($ia as $key => $row) {
            $index = $row['ITEMID'] . '--' . $row['WAREHOUSEID'] . '--' . $row['ASON'];
            $iaIndexShort[$index][] = $key;
            $index .= '--' . $row['DOCENTRYKEY'];
            $iaIndex[$index] = $key;
        }

        // get the item history, which is a summary-by-day, and can sometimes/somehow get out of synch....
        $history = $this->readItemHistory($restrictByDate);
        if ($history === false) {
            return false;
        }

        // add the history info into the item activity stuff so we can steal it below.....
        foreach ($history as $row) {
            // "SELECT itemkey as itemid, whsekey as warehouseid, ason, cost, qtywithvalue, extendedcost
            $index = $row['ITEMID'] . '--' . $row['WAREHOUSEID'] . '--' . $row['ASON'];
            foreach ( $iaIndexShort[$index] ?? [] as $iaKey) {
                $ia[$iaKey]['IH_COST'] = $row['EXTENDEDCOST'];
                $ia[$iaKey]['IH_V_QOH'] = $row['QTYWITHVALUE'];
                $ia[$iaKey]['IH_Q_QOH'] = $row['QTYONHAND'];
            }
        }

        // now we're done with the item history....
        unset($history);
        unset($iaIndexShort);


        // This will be our main driver for the output:
        $valuation = $this->runValuationQuery();
        if ($valuation === false) {
            return false;
        }
        // logFL("VALUATION:" . var_export($valuation,true));

        // So get what we need from the item activity query
        foreach ($valuation as $key => $row) {

            $index = $row['ITEMID'] . '--' . $row['WAREHOUSEID'] . '--' . $row['DATEIN'] . '--' . $row['DOCENTRYKEY'];
            $iaKey = $iaIndex[$index] ?? -1;
            if ($iaKey >= 0) {
                $valuation[$key]['NAME']            = $ia[$iaKey]['NAME'];
                $valuation[$key]['ASON']            = $ia[$iaKey]['ASON'];
                $valuation[$key]['DOCID']           = $ia[$iaKey]['DOCID'];
                $valuation[$key]['SPI']             = $ia[$iaKey]['SPI'];
                $valuation[$key]['UPDINV']          = $ia[$iaKey]['UPDINV'];
                $valuation[$key]['LOCATION']        = $ia[$iaKey]['LOCATION'];
                $valuation[$key]['ENTEREDDATE']     = $ia[$iaKey]['ENTEREDDATE'];
                $valuation[$key]['TRANSACTION_UOM'] = $ia[$iaKey]['TRANSACTION_UOM'];
                $valuation[$key]['COST_METHOD']     = $ia[$iaKey]['COST_METHOD'];
                $valuation[$key]['IA_QTY']          = $ia[$iaKey]['QUANTITY'];
                $valuation[$key]['IA_VALUE']        = $ia[$iaKey]['IAVALUE'];

                // how will we use these?
                $valuation[$key]['EXTENDEDCOST']    = $ia[$iaKey]['IH_COST'];
                $valuation[$key]['DAILY_V_QOH']    = $ia[$iaKey]['IH_V_QOH'];
                $valuation[$key]['DAILY_Q_QOH']    = $ia[$iaKey]['IH_Q_QOH'];

                // if this is a docentrycostkit record, then add an indicator to the dcc id that this is a kit PART.
                // like "Invoice ABC (Part)"
                if ($row['TYPE'] == 'DCK') {
                    $valuation[$key]['DOCID'] .= self::SKIT_PART;
                }
            }
        }

        // We're done with the item activity data, so free it up.
        unset($ia);
        unset($iaIndex);

        // sort the valuation table
        // by item, warehouse, Asof, docid, layer
        uasort ( $valuation, function ($a, $b) {
            $diff = strnatcmp( $a['ITEMID'], $b['ITEMID'] );
            if ($diff == 0) {
                $diff = strnatcmp( $a['WAREHOUSEID'], $b['WAREHOUSEID'] );
            }
            if ($diff == 0) {
                $diff = $this->MyCompareDate( $a['DATEIN'], $b['DATEIN'] );
            }
            if ($diff == 0) {
                // IN before OUT
                $aIn = ($a['IN_OUT'] == 'I') ? 0 : 1; // so in is 'lower' than out
                $bIn = ($b['IN_OUT'] == 'I') ? 0 : 1;
                if ($aIn < $bIn) {
                    $diff = -1;
                } else if ($aIn > $bIn) {
                    $diff = +1;
                }
            }
            if ($diff == 0) {
                $aDE = $a['DOCENTRYKEY'];
                $bDE = $b['DOCENTRYKEY'];
                if ($aDE < $bDE) {
                    $diff = -1;
                } else if ($aDE > $bDE) {
                    $diff = +1;
                }
            }
            if ($diff == 0) {
                $diff = $this->sqlDateTimeCompare( $a['ENTEREDDATE'], $b['ENTEREDDATE'] );
            }
            if ($diff == 0) {
                $diff = strnatcmp( $a['DOCID'], $b['DOCID'] );
            }
            if ($diff == 0) {
                $diff = strnatcmp( $a['LAYER'], $b['LAYER'] );
            }
            return $diff;
        }
        );
        return $valuation;
    }


    /**
     *      Run the queries for the VALUATION_VS_ITEM_ACTIVITY report, return the table of data ready to be displayed or exported
     *
     * @return bool|string[][]
     */
    public function runValuationVsItemActivityQueries()
    {
        $valuation = $this->runCommonQueries( false );

        // Ok, now we have a bunch-o-data in order.  We want to show INBOUND transactions,
        //    and then on the NEXT ROWS we shouw the OUTBOUND that took from that INBOUND as a layer...
        $inbound  = [];
        $outbound = [];
        foreach ($valuation as $row) {
            $this->getQOHValues($valuation, $row, $q_quantity, $v_quantity);
            if ($row['IN_OUT'] == 'I') {
                $inbound[] = $row;
            } else {
                $outbound[] = $row;
            }
        }

        // done with the bigger table, though the data is referenced so this may not save much....
        unset($valuation);


        // Index the outbound table so we can align the OUT to the IN
        $outByDocEntryCost = [];
        foreach ($outbound as $key => $row) {
            // DOCENTRYCOSTKITKEY points to a kit, so I've made kits negative so they align....
            $source = $row['DOCENTRYCOSTKEY'] ?: ( - ($row['DOCENTRYCOSTKITKEY'] ?? 0)); // is this right?
            $outByDocEntryCost[ $source ][] = $key;
        }


        // Now construct the resulting table:
        $firstTime      = true;
        $itemId         = '';
        $warehouseId    = '';
        $table          = [];
        foreach ($inbound as $row) {

            // Did the item or warehouse change?
            if (($itemId != $row['ITEMID']) || ($warehouseId != $row['WAREHOUSEID'])) {

                if ( ! $firstTime) {
                    if (isset($outByDocEntryCost[0])) {
                        $this->emitOutputWithNoInput($itemId, $warehouseId, $outByDocEntryCost[0], $outbound, $table);
                    }
                    $table[]    = [];       // put in a blank line
                }
                $firstTime      = false;
                $itemId         = $row['ITEMID'];
                $warehouseId    = $row['WAREHOUSEID'];
            }

            // Within the date range?
            // (we do this late rather than in the sql queries so we can find the outbound outside the window)
            if (($this->startDate != null) && ($this->MyCompareDate( $row['DATEIN'], $this->startDate ) < 0)) {
                continue;
            }
            if (($this->onOrBeforeDate != null) && ($this->MyCompareDate( $row['DATEIN'], $this->onOrBeforeDate ) > 0)) {
                continue;
            }


            $savedQtyLeft   = $row['QTYLEFT'] ?? 0;
            $qtyLeft        = $row['QUANTITY'] ?? 0;
            $row['QTYLEFT'] = $qtyLeft;             // because we're going to draw this down, below....
            $row['NOTES']   = '';
            $key            = count($table);        // remember where we are in the table so we can come back
            $table[]        = $row;
            $unitCost       = $row['UNITCOST'];
            $unitCostDate   = $row['DATEIN'];

            // now for the output records.....
            if (isset(   $outByDocEntryCost[ $row['RECORD#']])) {
                foreach ($outByDocEntryCost[ $row['RECORD#']] as $outboundIndex) {
                    $outRow = $outbound[ $outboundIndex ];

                    $qtyLeft                -= $outRow['QUANTITY'];
                    if ($this->MyCompareDate( $outRow['DATEIN'], $unitCostDate ) >= 0) {
                        $unitCostDate       = $outRow['DATEIN'];
                        $unitCost           = $outRow['UNITCOST'];
                    }
                    $whatToShow = [
                        'UNITCOST'          => $outRow['UNITCOST'],
                        'QTYLEFT'           => $qtyLeft,
                        'OUT_DATE'          => $outRow['DATEIN'],
                        'OUT_DOCID'         => $outRow['DOCID'],
                        'OUT_LAYER'         => $outRow['LAYER'],
                        'OUT_QUANTITY'      => $outRow['QUANTITY'],

                        'ENTEREDDATE'       => $outRow['ENTEREDDATE'],
                        'LOCATION'          => $outRow['LOCATION'],
                        'COST_METHOD'       => $outRow['COST_METHOD'],
                        'SPI'               => $outRow['SPI'],
                        'UPDINV'            => $outRow['UPDINV'],
                        'TRANSACTION_UOM'   => $outRow['TRANSACTION_UOM'],
                        'NOTES'             => $outRow['NOTES'] . "DocEntryCost (layer record#) is " . $outRow['RECORD#'] . '; ',
                    ];
                    $table[] = $whatToShow;
                }
            }

            $table[$key]['ON_VALUATION'] = "";
            $table[$key]['NOTES'] = "DocEntryCost is " . $row['RECORD#'] . "; ";
            if ($savedQtyLeft) {
                $table[$key]['ON_VALUATION'] = "YES";
                if ($qtyLeft != $savedQtyLeft) {
                    $table[$key]['ON_VALUATION'] = "YES BUT WRONG?";
                }
                $valuation = ibcmul($savedQtyLeft, $unitCost, 2, true);
                $table[$key]['NOTES'] .= "Valuation Report should show: Valuation $valuation; quantity $savedQtyLeft; unit cost $unitCost ; ";
            } else {
                $table[$key]['NOTES'] .= "Not on Valuation because quantity left is zero; ";
            }

            if ($qtyLeft != $savedQtyLeft) {
                $table[$key]['NOTES'] .= "The quantity left is $qtyLeft, but SHOULD BE $savedQtyLeft";
            }
        }
        return $table;
    }


    /**
     *      What is the SOURCE of the current layer, if one?
     *
     * @param       array       $allRows                   the list of all rows in the query
     * @param      int|string   $sourceDocEntryCostRef     reference to source docentrycost record
     *
     * @return string                                      the source, in English/Human
     */
    private function  getSource(&$allRows, $sourceDocEntryCostRef)
    {
        $rtn = "";
        if ($sourceDocEntryCostRef != 0) {
            // this is brute force and slow, but, ....
            foreach ($allRows as $row) {
                if ($row['RECORD#'] == $sourceDocEntryCostRef) {
                    $rtn = $row['ASON'] . " " . $row['DOCID'] . ' (' . $row['LAYER'] . ')';
                    break;  // FOUND IT
                }
            }
        }
        return $rtn;
    }


    /**
     *      How does THIS row affect QOH values, both QUANTITY and VALUE QOH values......
     *
     * @param       array       $allRows        the list of all rows in the query
     * @param       string[]    $row            properly constructed record from the various queries
     * @param       int|string  $q_quantity     really a decimal value, the QUANTITY quantity, can be zero
     * @param       int|string  $v_quantity     really a decimal value, the VALUE    quantity, can be zero
     *
     */
    private function getQOHValues(&$allRows, &$row, &$q_quantity, &$v_quantity)
    {
        $row['TXN_Q_V']   = $row['UPDINV'];             // from runItemActivityQuery(); does the DOCUMENT update Q or V?
        $row['LAYER_Q_V'] = $row['AFFECTS_INVENTORY'];  // from runValuationQuery(); does the LAYER update Q or V?

        $q_quantity = (($row['LAYER_Q_V'] == 'Q') || ($row['LAYER_Q_V'] == 'QV')) ? $row['QUANTITY'] : 0;
        $v_quantity = (($row['LAYER_Q_V'] == 'V') || ($row['LAYER_Q_V'] == 'QV')) ? $row['QUANTITY'] : 0;

        // S && P pay attention to the systemgenerated and adjdocentrycostkey
        if ($row['SPI'] != 'I') {
            $systemGenerated    = (($row['SYSTEMGENERATED']    ?? 'F') === 'T');
            $adjdocentrycostkey = (($row['ADJDOCENTRYCOSTKEY'] ??  0 ) != 0);

            // if system generated, then no cost, no quantity with value
            if ($systemGenerated) {
                $row['NOTES'] .= "(System Generated Layer); ";
                $v_quantity    = 0;
                $row['VALUE']  = "0";
            }

            // if adjustment, then no q quantty
            if ($adjdocentrycostkey) {
                $source = $this->getSource($allRows, $row['ADJDOCENTRYCOSTKEY']);
                $row['NOTES'] .= "(Adjustment to $source); ";
                $q_quantity    = 0;
            }
        }
        $row['Q_QTY']       = $q_quantity;
        $row['V_QTY']       = $v_quantity;

        if ($q_quantity == 0) {
            $row['IA_QTY'] = 0;
            $row['IA_VALUE'] = 0;
        }
    }


    /**
     *      Run the queries for the VALUATION_VS_ITEM_ACTIVITY report, return the table of data ready to be displayed or exported
     *
     * @return bool|string[][]
     */
    public function runQOHQueries()
    {
        $valuation   = $this->runCommonQueries( true );
        $table       = [];
        $itemId      = '';
        $warehouseId = '';
        $asOn        = '';
        $runningQQOH = 0;
        $runningVQOH = 0;
        foreach ($valuation as $row) {
            // Did the item or warehouse change?
            if (($itemId != $row['ITEMID']) || ($warehouseId != $row['WAREHOUSEID'])) {
                if ($itemId != '') {
                    $table[]    = [];       // put in a blank line
                }
                $itemId         = $row['ITEMID'];
                $warehouseId    = $row['WAREHOUSEID'];
                $asOn           = '';
                $runningQQOH    = 0;
                $runningVQOH    = 0;
            }

            // date change?
            if ($asOn != $row['ASON']) {
                $asOn           = $row['ASON'];
            } else {
                // date is same, blank out above daily numbers....
                $key            = count($table) - 1;
                if ($key >= 0) {
                    $table[$key]['DAILY_Q_QOH'] = '';
                    $table[$key]['DAILY_V_QOH'] = '';
                }
            }

            // Within the date range?
            // (we do this late rather than in the sql queries so we can find the outbound outside the window)
            if (($this->startDate != null) && ($this->MyCompareDate( $row['DATEIN'], $this->startDate ) < 0)) {
                continue;
            }
            if (($this->onOrBeforeDate != null) && ($this->MyCompareDate( $row['DATEIN'], $this->onOrBeforeDate ) > 0)) {
                continue;
            }

            if (($row['DOCENTRYCOSTKEY'] ?? 0) != 0) {
                $source = $this->getSource($valuation, $row['DOCENTRYCOSTKEY']);
                $row['NOTES'] .= "(Source is $source); ";
            }

            $this->getQOHValues($valuation, $row, $qqty, $vqty);

            if ($row['IN_OUT'] == 'I') {
                $runningQQOH += $qqty;
                $runningVQOH += $vqty;
            } else {
                $runningQQOH -= $qqty;
                $runningVQOH -= $vqty;
            }
            $row['RUNNING_Q_QOH'] = $runningQQOH;
            $row['RUNNING_V_QOH'] = $runningVQOH;
            $row['NOTES'] .= "DocEntryCost (layer record#) is " . $row['RECORD#'];
            $table[] = $row;
        }
        return $table;
    }


    /**
     *      Run the queries for the ALL_DETAILS report, return the table of data ready to be displayed or exported
     *
     * @return bool|string[][]
     */
    public function runDetailsQueries()
    {
        // ******************************************************************
        // 1) start with activity data (things that affect ON HAND)
        // ******************************************************************
        $ia = $this->runItemActivityQuery();
        if ($ia === false) {
            return false;
        }

        // make a convienient DocEntry index:
        $docEntries = [];
        $itemWhDays = [];
        foreach ($ia as $index => $row) {
            $key = $row['ITEMID'] . '--' . $row['DOCENTRYKEY'];
            $docEntries[$key] = $index;

            // and this alternate way of finding records and their amounts:
            $itemWhDays[$row['ITEMDIMKEY']][$row['WAREHOUSEDIMKEY']][$row['ASON']][$row['DOCENTRYKEY']] = $index;
        }

        // ******************************************************************
        // 2) then get valuation data
        // ******************************************************************
        $val = $this->runValuationQuery();
        if ($val === false) {
            return false;
        }

        // ******************************************************************
        // 3) get the item history table, used by the valuation report
        // ******************************************************************
        $history = $this->readItemHistory();

        // and assign it to the activity data via the docentrykey....
        $runningValueLeft   = 0;
        $runningValueItemWh = '';
        $dateLastRow        = '';
        $indexLastRow       = -1;
        foreach ($val as $row) {
            $item   = $row['ITEMID'];
            $wh     = $row['WAREHOUSEID'];
            $de     = $row['DOCENTRYKEY'];
            $key    = $item . '--' . $de;
            $index  = $docEntries[$key] ?? -1;
            if ($index < 0) {
                // may be outside the date range, since we don't filter by date
                continue;
            }

            // if this is a docentrycostkit record, then add an indicator to the dcc id that this is a kit PART.
            // like "Invoice ABC (Part)"
            if (($row['TYPE'] == 'DCK') && (strpos($ia[$index]['DOCID'], self::SKIT_PART) === false)) {
                $ia[$index]['DOCID'] .= self::SKIT_PART;
            }
            $ason        = $ia[$index]['ASON'];

            // ******************************************************************
            // 3A) we want to track variances between the itemhistory table
            //     and the docentrycost tables...
            // ******************************************************************
            // track running value left for this item, and the variance from running value at EOD
            $itemWh = $item . '--' . $wh;
            if ($runningValueItemWh != $itemWh) {
                $runningValueLeft   = 0;
                // $indexLastRow       = -1;  not really needed and the inspections complain
                $runningValueItemWh = $itemWh;
            } else if (($indexLastRow >= 0) && ($dateLastRow == $ason)) {
                // item history is per-day, so inter-day values will always fail.  Only report on the LAST date
                unset($ia[$indexLastRow]['VALUE_VARIANCE']);
            }


            // ******************************************************************
            // 3B) add itemhistory data
            // ******************************************************************
            // update the history columns
            $historyKey  = $item . '-' . $wh . '-' . $ason;
            if (isset($history[$historyKey])) {
                $ia[$index]['VALUATION_UNITCOST'] = $history[$historyKey]['COST'];
                $ia[$index]['VALUATION_EODQTY']   = $history[$historyKey]['QTYWITHVALUE'];
                $ia[$index]['VALUATION_EODVALUE'] = $history[$historyKey]['EXTENDEDCOST'];
            }

            // ******************************************************************
            // 3C) add docentrycost / docentrycostkits data
            // ******************************************************************
            if ($row['IN_OUT'] == 'I') {
                // there can be multiple entries for one docentry record if there are, for example, serial numbers.
                $ia[$index]['UNITCOST']   = $row['UNITCOST'];   // inbound may have multiple rows but we assume one unitcost
                $value                    = ibcmul($row['UNITCOST'], $row['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
                $runningValueLeft         = ibcadd($runningValueLeft, $value,ItemManager::BASEUNITPRECISION, true);
                $ia[$index]['ORIG_VALUE'] = ibcadd(($ia[$index]['ORIG_VALUE'] ?? 0), $value,ItemManager::BASEUNITPRECISION, true);
                $ia[$index]['VALUELEFT']  = ibcadd(($ia[$index]['VALUELEFT']  ?? 0), $value,ItemManager::BASEUNITPRECISION, true);
                $ia[$index]['QTYLEFT']    = ibcadd(($ia[$index]['QTYLEFT']    ?? 0), $row['QUANTITY'],ItemManager::BASEUNITPRECISION, true);
            } else { // IN_OUT must be 'O'
                // who does this row have as a SOURCE?  Does the SOURCE affect ONHAND?
                $sourceUnitCost = 0;
                if (isset($row['SOURCE_DOCENTRY'])) {
                    $key = $item . '--' . $row['SOURCE_DOCENTRY'];
                    if (isset($docEntries[$key])) {
                        $index2                   = $docEntries[$key];
                        $sourceUnitCost           = $ia[$index]['VALUATION_UNITCOST'] ?? 0;  // use today's average cost
                        $value                    = ibcmul($sourceUnitCost, $row['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
                        $runningValueLeft         = ibcsub($runningValueLeft, $value,ItemManager::BASEUNITPRECISION, true);
                        $ia[$index2]['VALUELEFT'] = ibcsub(($ia[$index2]['VALUELEFT']  ?? 0), $value,ItemManager::BASEUNITPRECISION, true);
                        $ia[$index2]['QTYLEFT']   = ibcsub(($ia[$index2]['QTYLEFT']    ?? 0), $row['QUANTITY'],ItemManager::BASEUNITPRECISION, true);
                    }
                } else {
                    $this->addNote($ia, $index, _("This entry has no source record"));
                }
                // Now update stuff on this row
                $ia[$index]['UNITCOST']   = $sourceUnitCost;
                $value                    = ibcmul($sourceUnitCost, $row['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
                $ia[$index]['ORIG_VALUE'] = ibcsub(($ia[$index]['ORIG_VALUE'] ?? 0), $value,ItemManager::BASEUNITPRECISION, true);
            }
            // we want a 'current value' that SHOULD match COGS.
            // So we need it to update inventory (not only quantity)
            // and we need it to decrement (sale/purch rtn/buildkit) or be a sales return
            if ((($ia[$index]['UPDINV'] == 'T') || ($ia[$index]['UPDINV'] == 'V')) &&
                ((($ia[$index]['INC_DEC'] == 'D') && ($ia[$index]['SPI'] != 'P')) || ($ia[$index]['SPI'] == 'S'))) {
                $value = ibcmul($row['UNITCOST'], $row['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
                $ia[$index]['CURRENT_VALUE'] = ibcadd($ia[$index]['CURRENT_VALUE'] ?? 0, $value, 2, true);   // this is a COGS amount we want
            }

            // ******************************************************************
            // 3D) now compute the variance, if one, for this row's itemhist vs
            //      docentrycost / docentrycostkits data
            // ******************************************************************
            // Compute the variance from the item hitory table to our running values
            $variance = ibcsub($ia[$index]['VALUATION_EODVALUE'], $runningValueLeft, ItemManager::BASEUNITPRECISION, true);
            if ($variance != 0) {
                $ia[$index]['VALUE_VARIANCE'] = $variance;
            }
            $indexLastRow = $index;
            $dateLastRow  = $ason;
        }

        // ******************************************************************
        // 4) Add COGS posting info
        // ******************************************************************
        $this->getCOGSInformation($itemWhDays, $ia);

        // Yet another pass (!) over the data to compute the variance between
        // the posted COGS amount and the current value
        foreach ($ia as $index => $row) {
            // ARE there cogs?  Maybe only on one side?
            if (isset($row['CURRENT_VALUE'])) {
                $cr = $row['GL_CR_AMT'] ?? 0;
                $dr = $row['GL_CR_AMT'] ?? 0;
                $cogs = $cr ?: $dr;
                $ia[$index]['COGS_DELTA'] = ibcsub($row['CURRENT_VALUE'], $cogs, ItemManager::AVERAGE_COST_DECIMALS, true);
            }
        }

        return $ia;
    }


    /**
     *      Query the item activity table and gather basic info on the item/warehouse/transaction
     *
     * @param bool $restrictByDate      should we restrict the query by date range?
     *
     * @return bool|string[][]
     */
    private function runItemActivityQuery($restrictByDate = true)
    {
        // The query below takes a LONG time, so this is an effort to reduce the amount of work in that query....
        $result = QueryResult(["SELECT record# from ictotal where cny# = :1 and name = 'ONHAND'", GetMyCompany()]);
        if (($result === false) || empty($result)) {
            return $result;
        }
        $totalsRecord = (int)$result[0]['RECORD#'];

        $qry   = [];
        $qry[] = "SELECT i.itemid, i.name, i.cost_method, de.unit as transaction_uom, ia.warehousekey warehouseid, dh.docid, ia.whencreated ason, i.record# as itemdimkey, w.record# as warehousedimkey,
                         dp.in_out as inc_dec, dp.sale_pur_trans as SPI, dp.updinv, ia.docentrykey, ia.quantity, (de.lineno + 1) as line_number, loc.name as location, dh.whenmodified as modified, dp.docid as docparid,
                         dh.auwhencreated as entereddate, ia.value as iavalue
                    FROM icitemmst i, dochdrmst dh, icitemactivity ia, docparmst dp, docentrymst de, locationmst loc, icwarehousemst w
                    WHERE i.cny# = :1 AND dh.cny# = i.cny# AND ia.cny# = i.cny# AND dp.cny# = i.cny# AND de.cny# = i.cny# AND loc.cny# = i.cny# AND w.cny# = i.cny#
                      AND ia.totalkey = $totalsRecord
                      AND ia.itemkey = i.itemid
                      AND ia.parentdochdrkey = dh.record#
                      AND de.record# = ia.docentrykey
                      AND de.locationkey = loc.record#
                      AND w.location_no = ia.warehousekey
                      AND dh.docparkey = dp.record#";

        $qry[] = GetMyCompany();
        $this->addItemWarehouseWhereClauses($qry, 'i.itemid', 'ia.warehousekey', ($restrictByDate) ? 'ia.whencreated' : '');
        $qry[0] .= " ORDER BY i.itemid, ia.warehousekey, ia.whencreated, dp.in_out desc, dh.docid";

        return QueryResult($qry);
    }


    /**
     *      Query the item history table and return an entry by item/wh/ason with the cost, qty, extended cost
     *
     * @param bool $restrictByDate      should we restrict the query by date range?
     *
     * @return bool|array       array by item/wh/date
     */
    private function readItemHistory($restrictByDate = true)
    {
        $qry = [];
        $qry[] = "SELECT itemkey as itemid, whsekey as warehouseid, ason, cost, qtywithvalue, extendedcost, qtyonhand
                    FROM itmhistcost
                    WHERE cny# = :1";
        $qry[] = GetMyCompany();
        $this->addItemWarehouseWhereClauses($qry, 'itemkey', 'whsekey', ($restrictByDate) ? 'ason' : '');
        $qry[0] .= " ORDER BY itemkey, whsekey, ason";

        $table = QueryResult($qry);
        if ($table === false) {
            return false;
        }

        $rtn = [];
        // note: I tried making a three-part key of [$item][$wh][$ason], but it took a long time and a lot of ram....
        foreach ($table as $row) {
            $item    = $row['ITEMID'];
            $wh      = $row['WAREHOUSEID'];
            $ason    = $row['ASON'];
            $key     = $item . '-' . $wh . '-' . $ason;
            // there SHOULD be one entry for each day there was a value transaction
            $rtn[$key] = $row;
        }
        return $rtn;
    }


    /**
     *      get data similar to what the valuation report would get.
     *
     * @return bool|array
     */
    private function runValuationQuery()
    {
        $qry = [];
        $qry[] = "SELECT itemkey as itemid, whsekey as warehouseid, docentrykey, unitcost, quantity, docentrycostkey, 0 as docentrycostkitkey, in_out, record#, 
                            datein, qtyleft, affects_inventory, value, systemgenerated, adjdocentrycostkey,
                            'DC' as type
                   FROM  docentrycost
                   WHERE cny# = :1
                     -- AND affects_inventory IN ('V','QV')
                     AND adjdocentrycostkey IS NULL";
        $qry[] = GetMyCompany();
        $this->addItemWarehouseWhereClauses($qry, 'itemkey', 'whsekey');
        $qry[0] .= " UNION
                  SELECT itemkey as itemid, whsekey as warehouseid, docentrykey, unitcost, quantity, docentrycostkey, docentrycostkitkey, in_out, (-1 * record#) as record#, 
                            datein, qtyleft, affects_inventory, value, 'F' as systemgenerated, 0 as adjdocentrycostkey,
                            'DCK' as type
                   FROM  docentrycostkits
                   WHERE cny# = :1
                     -- AND affects_inventory IN ('V','QV')";
        $this->addItemWarehouseWhereClauses($qry, 'itemkey', 'whsekey');
        $qry[0] .= " ORDER BY DOCENTRYKEY, record#, itemid, warehouseid, datein, in_out, affects_inventory";

        $rtn =  QueryResult($qry); // return an iterator for less memory overhead
        if ($rtn !== false) {
            // Having the source docentrycost isn't enough; we really want the source DOCENTRY.
            // Yes, I could get it with a more complicated sql query, but this seems simpler.
            $indexesToRecordNumbers = [];
            foreach ($rtn as $index => $row) {
                $indexesToRecordNumbers[$row['RECORD#']] = $index;
            }
            $docentry = 0;
            $layer    = 0;
            foreach ($rtn as $index => $row) {
                if (isset($row['DOCENTRYCOSTKEY'])) {
                    $sourceDocEntryCostIndex = $indexesToRecordNumbers[$row['DOCENTRYCOSTKEY']] ?? -1;
                    if ($sourceDocEntryCostIndex >= 0) {
                        $rtn[$index]['SOURCE_DOCENTRY'] = $rtn[$sourceDocEntryCostIndex]['DOCENTRYKEY'];
                    }
                }

                // For multy-layer items, lets assign an explicit layer number to keep things simpler....
                // we sorted by doentry and then item, so....
                if ($docentry != $row['DOCENTRYKEY']) {
                    $docentry  = $row['DOCENTRYKEY'];
                    $layer     = 0;
                }
                $layer++;
                $rtn[$index]['LAYER'] = $layer;
            }
        }
        return $rtn;
     }


    /**
     * @param bool|array      $ia                   item activity data
     * @param int             $itemHistoryIndex     index into item activity data
     * @param string          $note                 note to add
     */
     private function addNote(&$ia, $itemHistoryIndex, $note)
     {
         $alreadyANote = isset($ia[$itemHistoryIndex]["NOTES"]);
         if (!$alreadyANote || (strpos($ia[$itemHistoryIndex]["NOTES"], $note) === false)) {
             if ($alreadyANote) {
                 $ia[$itemHistoryIndex]["NOTES"] .= '; ';
             }
             $ia[$itemHistoryIndex]["NOTES"] = ($ia[$itemHistoryIndex]["NOTES"] ?? '') . $note;
         }
     }


    /**
     *      get COGS information for docentry records from deglresolves AND glentry
     *
     * @param   array           $itemWhDays         index into item activity data by item/wh/day
     * @param   bool|array      $ia                 item activity data
     *
     */
     private function getCOGSInformation(&$itemWhDays, &$ia)
     {
         $precision = 2;    // GL precision is only 2 places

         //  *****************************************************
         //  1) Get the resolve records (COGS)
         //     Normally, there is an item and warehouse dimension, but SOME CUSTOMERS forget....
         //  *****************************************************
         $query = [];
         $query[0] = "
            select  a.docentrykey, a.amount, ba.acct_no, ba.title, a.orig_trtype tr_type, b.account#, b.itemdimkey, b.warehousedimkey, a.glentrykey, b.entry_date, glb.batch_no, glb.batch_title
            from    deglresolve a, glentrymst b, baseaccountmst ba, glbatch glb
            where       a.cny#=:1 AND b.cny#=a.cny# AND ba.cny#=a.cny# AND glb.cny#=a.cny#
                    AND a.COGSPOSTING = 'T' 
                    and a.glentrykey=b.record# 
                    AND ba.record#=b.account#
                    AND glb.record# = b.batch#
                    ORDER BY a.docentrykey
            ";

         $query[] = GetMyCompany();
         $deglresolves = QueryIterable($query);
         if ($deglresolves === false) {
             return;
         }


         //  *****************************************************
         //  2) Update the Item Activity records with info on the COGS postings.
         //     Handle non-existant itemdimkey and warehousdimkey (unusual, bad customer practice!)
         //  *****************************************************
         $iaByDocentry = null;
         $resolveByGlEntryKey = [];
         $this->accounts = [];
         foreach ($deglresolves as $row) {
             // There can be hundreds of thousands of deglresolves, but there are usually only
             // a handfull of accounts in use, so it does save time to test....
             $account = $row['ACCOUNT#'] ?? 0;
             if ( ! isset($this->accounts[$account])) {
                 $this->accounts[$account] = ['NUM' => $row['ACCT_NO'], 'TITLE' => $row['TITLE'], 'KNOWN_TOTAL' => 0, 'OTHER_TOTAL' => 0];
             }
             // Sum the known totals
             $this->accounts[$account]['KNOWN_TOTAL'] = ibcadd($this->accounts[$account]['KNOWN_TOTAL'], $row['AMOUNT'], $precision,true);

             $drCr = ($row['TR_TYPE'] == -1) ? 'GL_CR_' : 'GL_DR_';    // debit or credit column?

             // use this to find the amounts in the glentries below....
             $resolveByGlEntryKey[$row['GLENTRYKEY']][] = $row['AMOUNT'];

             // Some customers, let's call them 'naughty' customers, don't use ITEMDIMKEY and WAREHOUSEDIMKEY in their
             // COGS postings, and that makes things nearly impossible for us, especially for KITS and STOCKABLE KITS.
             // However, since this is a recon report, let's try our best.....
             $missingDimKeys = ( ! isset($row['ITEMDIMKEY']) || ! isset($row['WAREHOUSEDIMKEY']));
             if ($missingDimKeys && ($iaByDocentry == null)) {
                 // Do this ONCE.....
                 $this->notes .= "\n" . _("* This customer is missing ITEMDIMKEYs / WAREHOUSEDIMKEYs in their GL") . "\n\n";
                 $iaByDocentry = [];    // now, even if it stays empty, it is not null.
                 foreach ($ia as $itemHistoryIndex => $iarow) {
                     // stockable kits are out.  Maybe kits as well.
                     if (($iarow['DOCPARID'] == StkitDocumentManager::BUILDKIT) || ($iarow['DOCPARID'] == StkitDocumentManager::DISKIT)) {
                         $this->addNote($ia, $itemHistoryIndex, _("Stockable Kit build/disassemble; cant resolve COGS entries without ITEM/WAREHOUSE dimension"));
                         $iaByDocentry[$iarow['DOCENTRYKEY']] = -1; // warning: unusable
                     } else {
                         if (isset($iaByDocentry[$iarow['DOCENTRYKEY']])) {
                             $note = _("Multipart txn, amount on ONE part; cant resolve COGS entries without ITEM/WAREHOUSE dimension");
                             $note2 = '';
                             if ($iaByDocentry[$iarow['DOCENTRYKEY']] >= 0) {
                                 $prevIHI = $iaByDocentry[$iarow['DOCENTRYKEY']];
                                 $this->addNote($ia, $prevIHI, $note);                          // tell original entry too
                                 $note2 = ' (' . _("see") . ' ' . $ia[$prevIHI]['ITEMID'] . ')';    // identify former entry
                             }
                             $this->addNote($ia, $itemHistoryIndex, $note . $note2);
                         } else {
                             $iaByDocentry[$iarow['DOCENTRYKEY']] = $itemHistoryIndex;
                         }
                     }
                 }
             }

             // now: are we missing dimension keys?  (ick!)
             if ($missingDimKeys) {
                 $itemHistoryIndex = $iaByDocentry[$row['DOCENTRYKEY']];
             } else {
                 $itemHistoryIndex = $itemWhDays[$row['ITEMDIMKEY']][$row['WAREHOUSEDIMKEY']][$row['ENTRY_DATE']][$row['DOCENTRYKEY']] ?? -1;
             }

             if ($itemHistoryIndex >= 0) {
                 $ia[$itemHistoryIndex][$drCr . "AMT"] = ibcadd($ia[$itemHistoryIndex][$drCr . "AMT"] ?? 0, $row['AMOUNT'], $precision, true);
                 $acctNum = ' ' . ($row['ACCT_NO'] ?? '??') . ' ';  // yes, a leading and trailing space
                 $acctNumAccum = $ia[$itemHistoryIndex][$drCr . "ACCT"] ?? $acctNum;
                 // we put a space before & after the acct# so we can find it with the strpos() below, and not find
                 // a PART of a number (like find 900 in 9000).  Note: very unusual case!
                 if (($acctNumAccum != $acctNum) && (strpos($acctNumAccum, $acctNum) === false)) {
                     $acctNumAccum .= 'and' . $acctNum; // so it is ' 1 and 2 '
                 }
                 $ia[$itemHistoryIndex][$drCr . "ACCT"] = $acctNumAccum;

                 // if no dimensions, it is hard to match an entry to a batch, so tell them which batch
                 if ($missingDimKeys) {
                     $note = $row['BATCH_NO'] . ':' . $row['BATCH_TITLE'];
                     $this->addNote($ia, $itemHistoryIndex, $note);
                 }
             }
         }

         $deglresolves->close(); // this saves a TON of ram (using an iterator)

         //  *****************************************************
         //  3) Get GL records by day for the items and warehouses for the accounts we found above
         //     Note: can't do anything about missing item/warehouse dim keys :-(
         //  *****************************************************
         $query = [];
         //  and itemdimkey is not null and warehousedimkey is not null
         $query[0] = "SELECT record#, itemdimkey, warehousedimkey, entry_date, account#, tr_type, amount
                     FROM glentrymst
                     WHERE cny#=:1 and itemdimkey is not null and warehousedimkey is not null
                     ";
         $query[] = GetMyCompany();
         $query = PrepINClauseStmt($query, array_keys($this->accounts), " AND account# ");
         $query[0] .= " order by itemdimkey, warehousedimkey, entry_date ";
         $glEntries = QueryIterable($query);
         if ($glEntries === false) {
             return;
         }


         //  *****************************************************
         //  4) Show GL amounts not shown above
         //  *****************************************************
         foreach ($glEntries as $row) {
             $varianceToday = $row['AMOUNT'];
             $glentryKey    = $row['RECORD#'];

             foreach ($resolveByGlEntryKey[$glentryKey] ?? [] as $resolveAmount) {
                 $varianceToday = ibcsub($varianceToday, $resolveAmount, 2, true);
             }

             // We subtracted off the stuff we know about.  Is there more there?
             // (or, is this an entry for something NOT our auto-generated COGS??)
             if ($varianceToday > 0) {
                 $account       = $row['ACCOUNT#'];
                 $accountNumber = $this->accounts[$account]['NUM'] ?? '????'; // should be there
                 $item          = $row['ITEMDIMKEY'];
                 $wh            = $row['WAREHOUSEDIMKEY'];
                 $entryDate     = $row['ENTRY_DATE'];
                 $tr_type       = (int)$row['TR_TYPE'];
                 // Sum the unknown totals
                 $this->accounts[$account]['OTHER_TOTAL'] = ibcadd($this->accounts[$account]['OTHER_TOTAL'], $varianceToday, $precision,true);

                 $drCr          = ($tr_type == -1) ? 'GL_CR_' : 'GL_DR_';    // debit or credit column?

                 // We want to find one entry to pawn this off onto if we can....
                 $itemHistoryIndexes = $itemWhDays[$item][$wh] ?? [];
                 $handled = false;
                 $foundTxnIndex = -1;
                 $drcrAcct = $drCr . "ACCT";
                 $accountNeedle = ' ' . $accountNumber . ' ';
                 foreach ($itemHistoryIndexes as $date => $rec) {
                     // we'll take the first entry for this item/wh on or after the date on the glentry
                     // that uses this account
                     if ($this->MyCompareDate($date, $entryDate) >= 0) {
                         foreach ($rec as $itemHistoryIndex) {
                             if (($ia[$itemHistoryIndex][$drcrAcct] == '') || (strpos($ia[$itemHistoryIndex][$drcrAcct], $accountNeedle) !== false)) {
                                 $foundTxnIndex = $itemHistoryIndex;
                                 break;  // just want the first
                             }
                         }
                         if ($foundTxnIndex >= 0) {
                             break;
                         }
                     }
                 }
                 // accumulate the 'variance' if we found a victim to attach it to
                 if ($foundTxnIndex >= 0) {
                     if ($ia[$foundTxnIndex][$drcrAcct] == '') {
                         $ia[$foundTxnIndex][$drcrAcct] = $accountNeedle;
                     }
                     $ia[$foundTxnIndex][$drCr . "VAR"] = ibcadd($ia[$foundTxnIndex][$drCr . "VAR"] ?? 0, $varianceToday, 2, true);
                     $handled = true;
                 }

                 if ( ! $handled) {
                     $this->notes .= sprintf(_("GL Post on %1s for account %2s of the amount %3s not shown above.\n"),$entryDate, $accountNumber, $varianceToday);
                 }
             }
         }
         $glEntries->close(); // iterators save a TON of ram
     }


    /**
     *      Compare date, but with a cache.
     *
     *  Turns out comparing dates takes comparitively LONG time.  Yet, there are only around 250 used dates per year,
     *  so a company may have around 1-2 thousand total dates in a few HUNDRED THOUSAND transaction records.
     *
     * @param string $d1        a date in system format
     * @param string $d2        a date in system format
     *
     * @return int              is -1 if d1 < d2, 0 if d1 == d2, +1 if d1 > d2
     */
    function MyCompareDate( $d1, $d2 )
    {
        static $cache = [];

        if ( ! isset($cache[ $d1 ])) {
            $cache[ $d1 ] = strtotime( $d1 );   // this is slow and many dates are the same over and over
        }
        if ( ! isset($cache[ $d2 ])) {
            $cache[ $d2 ] = strtotime( $d2 );   // this is slow and many dates are the same over and over
        }

        $c1 = $cache[ $d1 ];
        $c2 = $cache[ $d2 ];
        if ($c1 > $c2) {
            return +1;
        }
        if ($c1 < $c2) {
            return -1;
        }
        return 0;
    }


    /**
     * Is the first date greater-or-equal to the second date?
     * The parameters can be strings or DateTimes; where DateTimes are faster....
     * note: I do not expect booleans, but DateTime::createFromFormat returns tham, so inspections insist.
     *
     * @param string|DateTime|bool $earlierDate
     * @param string|DateTime|bool $laterDate
     *
     * @return bool
     */
    public function sqlDateTimeCompare ($earlierDate, $laterDate)
    {
        static $gmt = null;

        if ($gmt === null) {
            $gmt = new DateTimeZone("GMT");
        }

        if ($earlierDate instanceof DateTime) {
            $e = $earlierDate;
        } else {
            $e = DateTime::createFromFormat( 'j-M-y h.i.s.u A', $earlierDate, $gmt);
        }
        if ($laterDate instanceof DateTime) {
            $l = $laterDate;
        } else {
            $l = DateTime::createFromFormat( 'j-M-y h.i.s.u A', $laterDate, $gmt);
        }

        if (($e === false) || ($l === false)) {
            return false;   // not sure what else to do here.
        }

        return (($e > $l) ? +1 : (($e < $l) ? -1 : 0));
    }




}

