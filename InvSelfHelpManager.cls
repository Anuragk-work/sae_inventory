<?php

/**
 *  Inventory Self Help Manager
 *      Roger Collins, March 2023
 *
 *  Miscelanious self-help reports for customers
 *
 */

/**
 * Class InvCostToolManager
 */
class InvSelfHelpManager extends EntityManager
{
    const MAX_GRAPH_TABLE_SIZE      = 200;  // the graph of TDs maximum size



    /** @var array $translatedText */
    private $translatedText = [];

    /** @var InvCache $glGroups */
    private $glGroups = null;

    /** @var InvCache $items */
    private $items = null;

    /** @var InvCache $warehouses */
    private $warehouses = null;

    /** @var InvCache $docpar */
    private $docpar = null;

    /** @var array $docparGLs */
    private $docparGLs = null;

    /** @var InvCache $glAccounts */
    private $glAccounts = null;

    /** @var InvCache $transactions */
    private $transactions = null;

    /** @var InvCache $transactionsNotOurs */
    private $transactionsNotOurs = null;

    // /** @var array $preferences */
    // private $preferences = null;   // not used yet

    /** @var InvCache $locations */
    private $locations = null;

    /** @var InvCache $docentrycosts */
    private $docentrycosts = null;

    /** @var InvCache $itmhistcost */
    private $itmhistcost = null;

    /** @var InvCache $transactionCosts */
    private $transactionCosts = null;

    /** @var InvCache $selectDocHdrs */
    private $selectDocHdrs = null;          // specifically request doc headers

    /** @var InvCache $landedCosts */
    private $landedCosts = null;            // landed costs with and without targets

    /** @var array $decSeen */
    private $decSeen = null;                // docentrycost records seen

    /** @var InvCache $wheredUsedItems */
    private $wheredUsedItems =null;

    /**
     * Constructor
     */
    function __construct()
    {
        // Add tokens that will be used as headers for the generated tables.
        // Simplest if you use these names, minus the IA., for columns in SQL queries....
        $tokensWeUse = [
            'IA.ITEM', 'IA.WAREHOUSE', 'IA.DATE', 'IA.START_DATE', 'IA.END_DATE', 'IA.TRANSACTION',
            'IA.GL_GROUP', 'IA.DEBIT', 'IA.CREDIT', 'IA.DOCID', 'IA.NONE', 'IA.ACCOUNT', 'IA.MULTI_CURRENCY',
            'IA.DOCUMENT_DATE', 'IA.DOCUMENT_NAME', 'IA.ITEM', 'IA.WAREHOUSE', 'IA.CURRENCY',
            'IA.AMOUNT', 'IA.LOCATION', 'IA.BATCH_TITLE', 'IA.DEBIT_ACCOUNT', 'IA.CREDIT_ACCOUNT',
            'IA.DOCUMENT_TYPE', 'IA.ACCOUNT', 'IA.BATCH_DATE', 'IA.MODULEKEY', 'IA.QUANTITY', 'IA.QTY_ON_HAND',
            'IA.VALUATION', 'IA.AVERAGE_COST', 'IA.UNIT_COST', 'IA.ON_HAND', 'IA.QUANTITY_WITH_VALUE', 'IA.COST_METHOD',
            'IA.TRUE', 'IA.FALSE', 'IA.PARENT', 'IA.NO_GL', 'IA.SYMBOL', 'IA.EXTENDED_COST', 'IA.QTY_WITH_VALUE',
            'IA.LANDED_COST_TRANSACTION', 'IA.ADJUSTMENT_TRANSACTION', 'IA.TARGET_TRANSACTION_ID', 'IA.QUANTITY_LEFT',
            'IA.DEBITS', 'IA.CREDITS', 'IA.CUSTOMER_GL_GROUP', 'IA.VENDOR_GL_GROUP', 'IA.BASE_CURRENCY', 'IA.TXN_AMOUNT',
            'IA.LANDED_COST_AMOUNT', 'IA.TARGET', 'IA.ADJUSTMENT', 'IA.NOTES', 'IA.INVENTORY_VALUATION_REPORT',
            'IA.EMPTY', 'IA.YES', 'IA.NO', 'IA.DEBIT_OR_CREDIT', 'IA.COST', 'IA.OPEN_BOOKS', 'IA.QUANTITY_REMAINING',
            'IA.VALUATION_DEBIT', 'IA.VALUATION_CREDIT', 'IA.ACCOUNT_VALUATION_DR_DIFF', 'IA.ACCOUNT_VALUATION_CR_DIFF',
            'IA.CREATION_DATE', 'IA.UNMATCHED',
        ];

        foreach ($tokensWeUse as $token) {
            I18N::addToken($token);
        }

        $this->translatedText = I18N::getText();
    }

//  ****************************************************************************
//  ****************************************************************************
//
//  External routine called by Editor
//
//  ****************************************************************************
//  ****************************************************************************

    /**
     *      Generate one of our reports
     * @param string    $name       name of the report; must be one we recognize
     * @param string[]  $params     any optional parameters to be supplied
     *
     * @return bool                 true if CSV downloaded, false if error or warning msg
     */
    public function generateReport($name, $params)
    {
        self::sanitizeParams($params);
        $table = $this->dispatchOnReportName($name, $params);
        if ($table === false) {
            return false;
        }
        $ok = true;
        if (empty($table)) {
            Globals::$g->gErr->addIAError('INV-1437', __FILE__ . ":" . __LINE__, "Report is empty.");
            $ok = false;
        } else {
            $blob = $this->tableToCSV($table);
            $this->downloadCSV($name, $blob);
        }
        return $ok;
    }

    /**
     * UI pickers deliver "id--name" format, but we're really only interested in the "id" part,
     * so get rid of any unwanted suffixes. In addition, format dates to a canonical format
     * expected later.
     *
     * @param array $params Input parameters
     *
     * @return void
     */
    private static function sanitizeParams(array &$params)
    {
        $keysToSanitize = array_flip([ 'ITEM', 'WAREHOUSE', 'LOCATION' ]);
        $datesToSanitize = array_flip([ 'STARTDATE', 'ENDDATE' ]);
        foreach ($params as $key => $value) {
            if (array_key_exists($key, $keysToSanitize)) {
                $params[$key] = explode('--', $value)[0];
            } else if (array_key_exists($key, $datesToSanitize)) {
                if (!empty($value)) {
                    $date = new DateTimeImmutable($value);
                    $params[$key] = explode('T', $date->format('c'))[0];
                }
            }
        }
    }

    /**
     * @param array     $document       A document manager document, as you'd find in DocumentFormEditor
     * @param array     $ancestors      Array of rows of data for the ancestors
     * @param array     $descendants    Array of rows of data for the descendants
     *
     * @return bool                     ok?
     */
    public function getAncestorsAndDescendants($document, &$ancestors, &$descendants)
    {
        $ancestors   = [];
        $descendants = [];

        $ok = $this->cacheDocentrycostsFromDocument($document);
        if ($ok === false) {
            return false;
        }

        $startingDocEntryCosts = [];
        foreach ($this->docentrycosts as $docentrycost) {
            $startingDocEntryCosts[] = $docentrycost;
        }

        $ok = $ok && $this->findAncestors(  $startingDocEntryCosts, $ancestors);
        $ok = $ok && $this->findDescendants($startingDocEntryCosts, $descendants);

        return $ok;
    }


    /**
     * @param string    $name
     * @param string[]  $params
     *
     * @return array|bool
     */
    private function dispatchOnReportName($name, $params)
    {
        switch ($name) {
            case 'TransactionGraph':
                $table = $this->getDocumentGraph();
                break;

            case 'TransactionsByGLGroup':
            case 'TransactionsByAccount':
            case 'AccountsByTransaction':
                $table = $this->tdsByGlGroupOrAccount($name);
                break;

            case 'TransactionsPostingToGL':
            case 'ValuationByItem':
            case 'ValuationByGroup':
            case 'ValuationByAccount':
                $table = $this->transactionsPostingToGL($name, $params);
                break;

            case 'GLAccountNonInventoryDetail':
            case 'GLAccountNonInventorySummary':
                $table = $this->transactionsOtherThanInventory($name, $params);
                break;

            case 'AverageDailyCosts':
                $table = $this->averageDailyCosts($params);
                break;

            case 'ValuationSummary':
                $table = $this->valuationSummaryValue($params);
                break;

            case 'OpenPeriods':
                $table = $this->openPeriods();
                break;

            case 'LandedCosts':
                $table = $this->landedCosts($params);
                break;

            case 'ComponentWhereUsed':
                $table = $this->getComponentUsageTable($params);
                break;

            default:
                Globals::$g->gErr->addIAError(
                    'INV-1438',
                    __FILE__ . ":" . __LINE__,
                    "Report name '$name' is invalid.",
                    ['REPORT_NAME' => $name]
                );
                $table = false;
                break;
        }
        return $table;
    }




//  ****************************************************************************
//  ****************************************************************************
//
//  Reports
//
//  ****************************************************************************
//  ****************************************************************************

    /**
     *  Generate report: "List transaction definitions by GL Group"
     *
     * @param string  $reportType      by gl group or account or txn?
     * @return bool|array
     */
    private function tdsByGlGroupOrAccount($reportType)
    {
        $order = [
            // DRCR is the same field as the next field, so it starts a pair....
            'TransactionsByGLGroup' => ['GL_GROUP', 'CUSTOMER_GL_GROUP', 'DOCID', 'DEBIT_ACCOUNT', 'CREDIT_ACCOUNT' ],
            'AccountsByTransaction' => ['DOCID', 'GL_GROUP', 'ACCOUNT', 'DEBITS', 'CREDITS'],
            'TransactionsByAccount' => ['ACCOUNT', 'DOCID', 'GL_GROUP', 'DEBITS', 'CREDITS'],
        ];

        //  ************** HELPER **************

        /** @var callable $makeKey */
        $makeKey = function( $order, $fields, &$row ) {
            $keySkip = ['DEBITS', 'CREDITS', 'DEBIT_ACCOUNT', 'CREDIT_ACCOUNT'];
            $key = 'K'; // to make sure it is seen as a string
            foreach ($order as $field) {
                $row[$field] = $fields[$field] ?? '';
                if ( ! in_array($field, $keySkip)) {
                    $key .= $fields[$field] . ' ~ ';
                }
            }
            return $key;
        };

        // ************ MAIN CODE *************

        $ok = ($this->cacheGLGroups() && $this->cacheTDs(true) && $this->cacheGLAccts());
        if (!$ok) {
            return false;
        }

        // cache gl groups locally:
        $glGroupNameByKey    = [];
        $glGroupNameByKey[0] = GT($this->translatedText, 'IA.NONE');
        foreach ($this->glGroups as $glgroup) {
            $recordno                    = $glgroup['RECORD#'];
            $name                        = $glgroup['GL_GROUP'];
            $glGroupNameByKey[$recordno] = $name;
        }

        // and accounts:
        $glAccountNameByKey = [];
        $glAccountNameByKey[0] = GT($this->translatedText, 'IA.NONE');
        foreach ($this->glAccounts as $account) {
            $name = $account['ACCT_NO'] . '--' . $account['TITLE'] ?? '';
            $key  = $account['RECORD#'];
            $glAccountNameByKey[$key] = $name;
        }

        $hasAccounts = in_array('DEBIT_ACCOUNT', $order[$reportType]);
        $hasGroups   = in_array('DEBITS', $order[$reportType]);

        $hasAccountsList = [ 'DR' => 'DEBIT_ACCOUNT', 'CR' => 'CREDIT_ACCOUNT'];
        $hasGroupsList   = [ 'DR' => 'DEBITS',        'CR' => 'CREDITS'];

        // which of the two styles of reports are we doing?  One with accounts or one with gl groups?  (or neither)
        $listToUse       = $hasAccounts ? $hasAccountsList : ($hasGroups ? $hasGroupsList : []);

        $table           = [];
        foreach ($this->docpar as $docpar) {
            $row = [];
            $row['DOCID'] = $docpar['DOCID'];
            foreach ($docpar['GL'] as $gl) {
                $dr              = (($gl['DR_CR'] ?? '0') == '1');
                $glGroup         = $glGroupNameByKey[  $gl['GL_GROUPKEY']];  // key might be zero, so that becomes 'NONE'
                $custGLGroup     = $gl['CUSTOMER_GL_GROUP'];
                $row['GL_GROUP'] = $glGroup;
                $account         = $glAccountNameByKey[$gl['GL_ACCOUNTKEY']];  // if zero, it is 'none'
                $row['ACCOUNT']  = $account;
                $row['CUSTOMER_GL_GROUP']  = $custGLGroup;
                if ($custGLGroup !== '') {
                    $glGroup = "$glGroup ($custGLGroup)";   // for the DEBITS/CREDITS fields, append the customer gl group
                }
                if ($dr) {
                    $row['DEBIT_ACCOUNT']  = $account;
                    $row['CREDIT_ACCOUNT'] = '';
                    $row['DEBITS']         = $glGroup;
                    $row['CREDITS']        = '';
                } else {
                    $row['CREDIT_ACCOUNT'] = $account;
                    $row['DEBIT_ACCOUNT']  = '';
                    $row['CREDITS']        = $glGroup;
                    $row['DEBITS']         = '';
                }

                $key = $makeKey($order[$reportType], $row, $thisRow);

                // is this row similar to others, or new?
                if (isset($table[$key])) {
                    // we might have multiple entries, each with a debit or credit, so see if there is room....
                    // (usually folks assign one DR then one CR, but not always)
                    $found = false;
                    $free  = -1;
                    $fieldToCheck = -1;
                    foreach ($table[$key] as $index => $oneTableEntry) {

                        $fieldToCheck = $listToUse[ $dr ? 'DR' : 'CR'];

                        // is it already there?
                        if ($oneTableEntry[$fieldToCheck] === $thisRow[$fieldToCheck]) {
                            $found = true;
                            break;
                        }

                        // could we use this row potentially?
                        if ($oneTableEntry[$fieldToCheck] === '') {
                            $free = $index;
                        }
                    }

                    // if we found it, we're done.  If not....
                    if ( !$found ) {
                        // Did we found a free row?
                        if ($free >= 0) {
                            $table[$key][$free][$fieldToCheck] = $thisRow[$fieldToCheck];
                        } else {
                            // not found, then we need to add a new entry under this key
                            $table[$key][] = $thisRow;
                        }
                    }
                } else {
                    // the key is not in the table, add this row as the first entry for that key
                    $table[$key] = [$thisRow];
                }
            }
        }

        ksort($table);   // put it in order by key

        // flatten the table....
        $rtn = [];
        foreach ($table as $entriesForOneKey) {
            foreach ($entriesForOneKey as $row) {
                $rtn[] = $row;
            }
        }
        return $rtn;
    }


    /**
     *  Given a transaction record, fetch the COSTQUANTITY and COSTAMOUNT from the docentrycost record(s)
     *      Note that the costs and quantity can be different from the docentry for kits and stockable kits, and if
     *      the customer updated costs with MIV but it is one of those non-inventory transactions where we don't
     *      always update docentry costs with sum(docentrycosts) (why not?)
     *
     * @param string[]  $transaction    The transaction read from $this->transactions and with ITEM filled in
     */
    private function getCostsForGLRecord(&$transaction)
    {
        static $cachedDocentrykey     = 0;  // we ask for the docentrykey at least twice, sometimes more
        static $cachedDocentryRecords = [];

        $docentryKey = $transaction['DEREC'];   // the docentry record#
        if ($docentryKey != $cachedDocentrykey) {
            $cachedDocentrykey     = $docentryKey;
            // this could come back with an empty array.....
            $cachedDocentryRecords = $this->transactionCosts->getByKey('DOCENTRYKEY', $cachedDocentrykey);
        }

        $itemID     = $transaction['ITEM'];
        $cQuantity  = 0;
        $cAmount    = 0;
        $isInbound  = true;     // true for IN, false for OUT
        $found      = false;    // did we find any docentrycost records?
        $kitPosting = ($transaction['ITEM_TYPE'] === 'K') && ($transaction['REVPOSTING'] === 'K');

        foreach ($cachedDocentryRecords as $cost) {
            // Note: the valuation conributions to itmhistcost IGNORE cost records that adjust others.
            //      Then it takes the ADJUSTED cost and applies it there.  Even though cost > gl post.

            // Note: a KIT with KIT posting doesn't affect the valuation, but its PARTS do.  SUM the costs....
            if ($kitPosting || ($itemID === $cost['ITEMKEY'])) {

                // the costs apply to the valuation based on the direction;
                // if the caller is looking for debits, then take incoming costs, else outgoing.

                $isInbound = (($cost['IN_OUT'] ?? '') === 'I');     // all the same item/wh have the same direction
                $keep      = true;
                // if there is no gl record then there is no TR_TYPE, so assume this cost record is for us
                if (isset($transaction['TR_TYPE'])) {
                    $isDebit = ($transaction['TR_TYPE'] == 1); // -1 is credit (no gl == no tr_type)
                    $keep    = ($isDebit === $isInbound);
                }

                $decSeenKey = $cost[InvCache::NameOfRowField];
                if ( $keep &&
                     ( ! $this->decSeen[$decSeenKey])) {
                    $valueOnly = ($cost['AFFECTS_INVENTORY'] === 'V');
                    $qtyOnly   = ($cost['AFFECTS_INVENTORY'] === 'Q');
                    if ( ! $valueOnly) {
                        $cQuantity = round($cQuantity + $cost['QUANTITY'], 8);
                    }

                    if ( ! $qtyOnly) {
                        $cAmount = round($cAmount + $cost['COST'], 8); // not contributed cost, so we get adjusted values
                    }
                    $found     = true;
                    $this->decSeen[$decSeenKey] = true; // remember we've seen this one already
                }
            }
        }

        $transaction['COSTSFOUND'] = $found;

        if ( ! $found) {
            // direction of the transaction, not the item
            $docParKey = $transaction['DOCPARKEY'];
            $docParRec = $this->docpar->getByKey('RECORD#', $docParKey);
            $isInbound = (($docParRec['IN_OUT'] ?? '') === 'I');
        }

        $transaction['COSTQUANTITY'] = $cQuantity;
        $transaction['COSTAMOUNT']   = $cAmount;
        $transaction['COSTINBOUND']  = $isInbound;
    }


    /**
     *  Get transactions that fo NOT post to the GL, but DO have an effect on valuation
     *
     * @param int[]    $docEntrySeen        docentry records seen in the main report
     *
     * @return bool                         SQL result
     */
    private function getCostsNotSeen($docEntrySeen)
    {
        // Get the lists of docentrykeys that are NOT in $docEntrySeen
        $costsNotSeen = [];
        foreach ($this->transactionCosts as $oneCost) {
            $docentryKey = $oneCost["DOCENTRYKEY"];
            if ( ! isset($docEntrySeen[$docentryKey])) {
                $costsNotSeen[$docentryKey] = true;     // remove dups
            }
        }

        // get the transactions for the UNSEEN docentrys...
        if ($this->cacheDocHdrsFromList(array_keys($costsNotSeen)) === false) {
            return false;
        }

        return true;
    }


    /**
     *  List transactions that post to the GL
     *
     * @param string    $name       the report name
     * @param array     $params     the parameters like start and end date
     *
     * @return array|bool
     */
    private function transactionsPostingToGL($name, $params)
    {
        // ****************************
        // ********* HELPERS **********
        // ****************************

        // add a UNIQUE note
        /** @var callable $addNote */
        $addNote = function(&$transaction, $newNote) {
            if ($newNote != '') {
                $notes = $transaction['NOTES'] ?? '';
                if ($notes == '') {  // no existing notes?
                    $transaction['NOTES'] = $newNote;
                } else if (strpos($notes, $newNote) === false) {   // are the notes unique?
                    $transaction['NOTES'] .= "; $newNote";         // yes, append the new notes to the end of the old notes
                }
            }
        };

        /** @var callable $getItem  lookup the item record for the itemID or itemKey, whichever we have */
        $getItem = function(&$transaction) use ($addNote) {
            // get the item record based on the itemid or itemdimkey
            // we prefer the itemdimkey
            if (isset($transaction['ITEMDIMKEY']) && ($transaction['ITEMDIMKEY'] > 0)) {
                $itemRec = $this->items->getByKey('RECORD#', $transaction['ITEMDIMKEY']);
            } else {
                $itemRec = $this->items->getByKey('ITEM', ($transaction['DEITEM'] ?? $transaction['ITEM']));
            }
            $transaction['ITEM']        = $itemRec['ITEM'] ?? '??';
            $transaction['GL_GROUP']    = $this->glGroup($itemRec['GL_GROUP'] ?? 0);
            $transaction['COST_METHOD'] = $itemRec['COST_METHOD'] ?? '';
            $transaction['ITEM_TYPE']   = $itemRec['ITEM_TYPE'] ?? '??';
            $transaction['REVPOSTING']  = $itemRec['REVPOSTING'] ?? '??';
            $it = $transaction['ITEM_TYPE'];
            if ( ! in_array($it, ['I', 'SK'] )) {
                $addNote($transaction, " ($it)");
            }
        };


        /** @var callable $collapseSimilarEntries    see if we can summ similar records (those with the same $key value */
        $collapseSimilarEntries = function(&$table, $key, $row, $drCrAcctsNeeded, $valuationReport, $valuationNeeded,
                                            $itmHistCostNeeded, $quantityNeeded, $isDebit) use ($addNote) {
            $found = false;
            if (isset($table[$key])) {
                // lets see if we can congeal the debit or credit accounts togeather
                if ($drCrAcctsNeeded) {
                    $foundAt = -1;
                    $blankAt = -1;
                    // pass one: where should this entry go?
                    foreach ($table[$key] as $index => $entry) {
                        if ($isDebit) {
                            if (($blankAt < 0) && ($entry['DEBIT_ACCOUNT'] == '')) {
                                $blankAt = $index;  // ok so here is a blank entry, first one wins
                            }
                            if ($entry['DEBIT_ACCOUNT'] == $row['DEBIT_ACCOUNT']) {
                                $foundAt = $index;
                                break;  // look no further
                            }
                        } else {
                            if (($blankAt < 0) && ($entry['CREDIT_ACCOUNT'] == '')) {
                                $blankAt = $index;  // ok so here is a blank entry, first one wins
                            }
                            if ($entry['CREDIT_ACCOUNT'] == $row['CREDIT_ACCOUNT']) {
                                $foundAt = $index;
                                break;  // look no further
                            }
                        }
                    }

                    // Pass two
                    // if no room for this record and not already present, hen create a new one....
                    // OTHERWISE.....
                    $indexToUse = ($foundAt !== -1) ? $foundAt : $blankAt;
                    if ($indexToUse !== -1) {   // found or blank
                        $found = true;
                        if ($isDebit) {
                            $table[$key][$indexToUse]['DEBIT_ACCOUNT']  = $row['DEBIT_ACCOUNT'];    // might already be there, but thats ok
                        } else { // is credit
                            $table[$key][$indexToUse]['CREDIT_ACCOUNT'] = $row['CREDIT_ACCOUNT'];    // might already be there, but thats ok
                        }
                    }
                } else {
                    $found = true;  // well, we didn't NEED to find them
                    $indexToUse = 0;
                    if (count($table[$key]) != 1) {
                        throw new Exception("[CODE BUG] table with $key has count other than 1.");
                    }
                }

                // summarize the valuation and itmhistcost on the found existing row
                if ($found) {
                    if ($isDebit) {
                        $table[$key][$indexToUse]['DEBIT']  = round(($table[$key][$indexToUse]['DEBIT'] ?? 0) + ($row['DEBIT'] ?? 0), 8);
                    } else {
                        $table[$key][$indexToUse]['CREDIT'] = round(($table[$key][$indexToUse]['CREDIT'] ?? 0) + ($row['CREDIT'] ?? 0), 8);
                    }
                    if ($valuationNeeded) {
                        $table[$key][$indexToUse]['VALUATION_DEBIT']  = round(($table[$key][$indexToUse]['VALUATION_DEBIT']  ?? 0) + ($row['VALUATION_DEBIT']  ?? 0), 8);
                        $table[$key][$indexToUse]['VALUATION_CREDIT'] = round(($table[$key][$indexToUse]['VALUATION_CREDIT'] ?? 0) + ($row['VALUATION_CREDIT'] ?? 0), 8);
                        $table[$key][$indexToUse]['ACCOUNT_VALUATION_DR_DIFF'] = round(($table[$key][$indexToUse]['ACCOUNT_VALUATION_DR_DIFF'] ?? 0) + ($row['ACCOUNT_VALUATION_DR_DIFF'] ?? 0), 8);
                        $table[$key][$indexToUse]['ACCOUNT_VALUATION_CR_DIFF'] = round(($table[$key][$indexToUse]['ACCOUNT_VALUATION_CR_DIFF'] ?? 0) + ($row['ACCOUNT_VALUATION_CR_DIFF'] ?? 0), 8);
                    }
                    if ($itmHistCostNeeded) {
                        $table[$key][$indexToUse]['AVERAGE_COST'] = round(($table[$key][$indexToUse]['AVERAGE_COST'] ?? 0) + ($row['AVERAGE_COST'] ?? 0), 8);
                    }
                    if ($quantityNeeded) {
                        $q = $row['QUANTITY'] ?? 0;
                        $table[$key][$indexToUse]['QUANTITY'] = round(($table[$key][$indexToUse]['QUANTITY'] ?? 0) + $q, 8);
                    }
                    if ($valuationReport) {
                        $table[$key][$indexToUse]['INVENTORY_VALUATION_REPORT'] = round(($table[$key][$indexToUse]['INVENTORY_VALUATION_REPORT'] ?? 0.0) + ($row['INVENTORY_VALUATION_REPORT'] ?? 0.0), 8);
                    }

                    // combine notes fields
                    $addNote($table[$key][$indexToUse], $row['NOTES'] ?? '');
                }
            }
            return $found;
        };

        /** @var callable $buildRow   create the row of values and the key to store it under */
        $buildRow = function(&$row, $transaction, $fields, $numericFields, $ignoreInKeys, $gmt) {

            $key = 'K';
            $row = [];
            foreach ($fields as $field) {
                $ignoreInKey = in_array($field, $ignoreInKeys);
                $isNumeric   = in_array($field, $numericFields);
                $value       = $transaction[$field] ?? ($isNumeric ? 0 : '');
                $row[$field] = $value;
                // the key does not include the amounts so we can summarize them
                if ( ! $ignoreInKey) {
                    if ($field === 'DOCUMENT_DATE') {
                        // go from M/D/Y to Y/M/D do it sorts properly; defensively populate a value just in case...
                        $value = !empty($value) ? $value : '01/01/1970';
                        $theDate = DateTime::createFromFormat('m/d/Y', $value, $gmt);
                        $value   = $theDate->format('Y-m-d');
                    }
                    $value = str_replace(' ', '~', $value);  // help the sort.  So '1' comes before '1 HAMMER'
                    $key  .= $value . ' ';
                }
            }
            return $key;
        };


        /** @var callable $preComputeValuationByGLByItemWarehouse */
        $preComputeValuationByGLByItemWarehouse = function( & $ratioGLAmountByItemWarehouse) {

            $accounts = $this->accountsForInventoryValuation();
            if ($accounts === false) {
                return false;
            }

            // Do a pre-pass to figure out the total amount BY GL ACCOUNT for each item/wh
            $ratioGLAmountByItemWarehouse = [];
            $totalGLAmountByItemWarehouse = [];
            $totalAmountByItemWarehouse = [];
            foreach ($this->transactions as $transaction) {
                // we expect the itemdimkey in the GL.  Elsewhere we allow just the docentry item,
                // but for this calculation let's assume it is there.

                // $accounts[$account][$in]
                $isDebit    = (($transaction['TR_TYPE'] ?? 0) == 1); // -1 is credit (no gl == no tr_type)
                $account    = $transaction['ACCOUNT#'];
                $use        = $accounts[$account][$isDebit] ?? false;

                if ($use && isset($transaction['ITEMDIMKEY'])) {
                    $amount     = $transaction['DEGLRESOLVE_AMOUNT'] ?? 0.00;
                    $amount     = $isDebit ? $amount : (-$amount);
                    $itemKey    = $transaction['ITEMDIMKEY'];
                    $warehouse  = $transaction['WAREHOUSE'];
                    $prevAmpunt = $totalAmountByItemWarehouse[$itemKey][$warehouse] ?? 0.00;
                    $totalAmountByItemWarehouse[$itemKey][$warehouse] = round($prevAmpunt + $amount, 10);  // total for i/w
                    $prevAmpunt = $totalGLAmountByItemWarehouse[$itemKey][$warehouse][$account] ?? 0.00;
                    $totalGLAmountByItemWarehouse[$itemKey][$warehouse][$account] = round($prevAmpunt + $amount, 10);  // this is the amount
                }
            }

            // apportion the amounts over the places it is used
            foreach ($totalGLAmountByItemWarehouse as $itemKey => $whs) {
                foreach ($whs as $warehouse => $accts) {
                    foreach ($accts as $account => $amount) {
                        $totalOverAllAccounts = $totalAmountByItemWarehouse[$itemKey][$warehouse];
                        $ratioGLAmountByItemWarehouse[$itemKey][$warehouse][$account] =
                            ($totalOverAllAccounts == 0) ? 0 : round($amount / $totalOverAllAccounts, 10);
                    }
                }
            }
            return true;
        };

        /** @var callable $fillInTransactionData */
        $fillInTransactionData = function(&$transaction, $inLocationField, $inLocFalse, $none) use ($addNote, $getItem) {

            $locationRecord                = $this->locations->getByKey('RECORD#', $transaction['LOCATION#']);
            $transaction['LOCATION']       = $locationRecord['LOCATION'] ?? '';

            $getItem($transaction);

            $isParentLocation = false;
            if ($inLocationField != '') { // are we paying attention to the location?
                $isParentLocation = $transaction['PARENT'] ?? false;
                if ($isParentLocation) {
                    $addNote($transaction, $inLocFalse);    // put it into the notes for now
                }
            }

            // direction of the transaction, not the item
            if (isset($transaction['TR_TYPE'])) {
                $isDebit = (($transaction['TR_TYPE'] ?? 0) == 1); // -1 is credit (no deglresole means no TR_TYPE)
            } else {
                $docParKey = $transaction['DOCPARKEY'];
                $docParRec = $this->docpar->getByKey('RECORD#', $docParKey);
                $isDebit   = (($docParRec['IN_OUT'] ?? '') === 'I');
                $transaction['TR_TYPE'] = $isDebit ? 1 : -1;
            }

            $acctNo      = $transaction['ACCOUNT#'] ?? 0;
            $account     = ($acctNo > 0) ? $this->glAccounts->getByKey('RECORD#', $acctNo) : null;
            $accountName = ($account === null) ? $none : (($account['ACCT_NO'] ?? '??') . '--' . ($account['TITLE'] ?? ''));
            $amount      = $transaction['DEGLRESOLVE_AMOUNT'] ?? 0.00;

            // if we're looking at a parent location, don't show the GL stuff because
            // it would not show up on a GL report.  The VALUATION report, however, might
            if ($isParentLocation) {
                $transaction['CREDIT']     = 0.00;
                $transaction['DEBIT']      = 0.00;
            } else {
                $transaction['CREDIT']     = $isDebit ? 0.00 : (float)$amount;
                $transaction['DEBIT']      = $isDebit ? (float)$amount : 0.00;
            }
            $transaction['CREDIT_ACCOUNT'] = $isDebit ? '' : $accountName;
            $transaction['DEBIT_ACCOUNT']  = $isDebit ? $accountName : '';
            $transaction['ACCOUNT']        = $accountName;

            // lookup the docentrycost[kits] records....
            $this->getCostsForGLRecord($transaction);
            $isInbound      = $transaction['COSTINBOUND'];
            $valuation      = (float)$transaction['COSTAMOUNT'];
            $quantity       = (float)($transaction['QUANTITY'] ?: ($transaction['COSTQUANTITY']));
            $valuationDiff  = round($amount - $valuation, 8);

            // The all-important valuation columns (its why we're here!)
            // "Why doesn't the GL match the Valuation Report?"
            if ($isDebit) {
                $transaction['VALUATION_DEBIT']   = $valuation;
                $transaction['VALUATION_CREDIT']  = 0;
                $transaction['ACCOUNT_VALUATION_DR_DIFF'] = $valuationDiff;
                $transaction['ACCOUNT_VALUATION_CR_DIFF'] = 0;
            } else {
                $transaction['VALUATION_DEBIT']   = 0;
                $transaction['VALUATION_CREDIT']  = $valuation;
                $transaction['ACCOUNT_VALUATION_DR_DIFF'] = 0;
                $transaction['ACCOUNT_VALUATION_CR_DIFF'] = $valuationDiff;
            }

            $transaction['QUANTITY']    = $isInbound ? $quantity  : (-$quantity);
        };



        // ****************************
        // ******** MAIN CODE *********
        // ****************************
        $order = [
            'TransactionsPostingToGL' => ['DOCUMENT_DATE', 'CREATION_DATE', 'DOCUMENT_NAME', 'ITEM', 'COST_METHOD', 'WAREHOUSE', 'QUANTITY', 'CURRENCY', 'BASE_CURRENCY', 'LOCATION', 'DEBIT_ACCOUNT', 'CREDIT_ACCOUNT', 'DEBIT', 'CREDIT', 'BATCH_TITLE', 'GL_GROUP', 'VALUATION_DEBIT', 'VALUATION_CREDIT', 'ACCOUNT_VALUATION_DR_DIFF', 'ACCOUNT_VALUATION_CR_DIFF', /* 'INVENTORY_VALUATION_REPORT', */ 'NOTES' ],
            'ValuationByItem'         => ['ITEM', 'QUANTITY', 'ACCOUNT', 'CURRENCY', 'DEBIT', 'CREDIT', 'GL_GROUP', 'VALUATION_DEBIT', 'VALUATION_CREDIT', 'ACCOUNT_VALUATION_DR_DIFF', 'ACCOUNT_VALUATION_CR_DIFF', /* 'INVENTORY_VALUATION_REPORT', */ 'NOTES' ],
            'ValuationByGroup'        => ['GL_GROUP', 'ACCOUNT', 'CURRENCY', 'DEBIT', 'CREDIT', 'VALUATION_DEBIT', 'VALUATION_CREDIT', 'ACCOUNT_VALUATION_DR_DIFF', 'ACCOUNT_VALUATION_CR_DIFF', /* 'INVENTORY_VALUATION_REPORT', */ 'NOTES'],
            'ValuationByAccount'      => ['ACCOUNT', 'CURRENCY', 'DEBIT', 'CREDIT', 'VALUATION_DEBIT', 'VALUATION_CREDIT', 'ACCOUNT_VALUATION_DR_DIFF', 'ACCOUNT_VALUATION_CR_DIFF', /* 'INVENTORY_VALUATION_REPORT', */ 'NOTES' ],
        ];

        $reportFields      = $order[$name];
        $itmHistCostNeeded = in_array('AVERAGE_COST',    $reportFields);
        $valuationNeeded   = in_array('VALUATION_DEBIT', $reportFields);
        $drCrAcctsNeeded   = in_array('DEBIT_ACCOUNT',   $reportFields) || in_array('CREDIT_ACCOUNT', $reportFields);
        $quantityNeeded    = in_array('QUANTITY',        $reportFields);
        $valuationReport   = in_array('INVENTORY_VALUATION_REPORT', $reportFields);
        $gmt               = new DateTimeZone("GMT");

        // Are we processing a specific-location or everything?
        $noGL            = GT($this->translatedText, 'IA.NO_GL');
        $inLocFalse      = GT($this->translatedText, 'IA.PARENT');
        $none            = GT($this->translatedText, 'IA.NONE');
        $inLocationField = '';
        if (isset($params['LOCATION'])) {
            $inLocationField = 'IN'; // TODO: find a better name for it
        }

        $numericFields  = ['DEBIT', 'CREDIT', 'VALUATION_DEBIT', 'VALUATION_CREDIT', 'AVERAGE_COST', 'QUANTITY', 'ACCOUNT_VALUATION_DR_DIFF', 'ACCOUNT_VALUATION_CR_DIFF', 'INVENTORY_VALUATION_REPORT' ];
        $ignoreInKeys   = array_merge($numericFields, ['DEBIT_ACCOUNT', 'CREDIT_ACCOUNT', 'NOTES' ]); // ignore these fields in the summation keys

        $ok = ($this->cacheItems() && $this->cacheGLGroups() && $this->cacheGLAccts() && $this->cacheLocations()
            && $this->cacheTDs(false) && $this->cacheGLTransactions($params) && $this->cacheCosting($params));

        if ($valuationReport) {
            // figure out proportions of amunts per gl account per item per warehouse
            $ok = $ok && $preComputeValuationByGLByItemWarehouse($ratioGLAmountByItemWarehouse);
        }

        if (!$ok) {
            return false;
        }

        // Let's make a table of what we want....
        $docEntrySeen = [];
        $table        = [];
        foreach ($this->transactions as $transaction) {

            $docEntrySeen[$transaction['DEREC']] = true;  // ok, saw this one

            // do all the common gathering of data
            $fillInTransactionData($transaction, $inLocationField, $inLocFalse, $none);

            // Summarize the fields for the report.
            // Step 1: Make the row of fields, and a key with the fields we sumarize over
            $row = [];
            $key = $buildRow($row, $transaction, $reportFields, $numericFields, $ignoreInKeys, $gmt);

            // Step 2: Maybe we can summarize the record, maybe not
            $isDebit    = (($transaction['TR_TYPE'] ?? 0) == 1); // -1 is credit
            $found      = $collapseSimilarEntries($table, $key, $row, $drCrAcctsNeeded, $valuationReport,
                                                $valuationNeeded, $itmHistCostNeeded, $quantityNeeded, $isDebit);
            if (!$found) {
                $table[$key][] = $row;        // never seen it before
            }
        }

        // For any docentry we have costs for but have NOT seen, lets make a record too....
        $costsNotSeenOk = $this->getCostsNotSeen($docEntrySeen);
        if ($costsNotSeenOk === false) {
            return false;
        }
        foreach ($this->selectDocHdrs as $transaction) {

            // do all the common gathering of data
            $fillInTransactionData($transaction, $inLocationField, $inLocFalse, $none);

            // build the row and key, combine similar keys
            $row = [];
            $key = $buildRow($row, $transaction, $reportFields, $numericFields, $ignoreInKeys, $gmt) . ' P2';

            $isDebit    = (($transaction['TR_TYPE'] ?? 0) == 1); // -1 is credit
            $found      = $collapseSimilarEntries($table, $key, $row, $drCrAcctsNeeded, $valuationReport,
                                                $valuationNeeded, $itmHistCostNeeded, $quantityNeeded, $isDebit);
            if (!$found) {
                $addNote($row, $noGL);         // no GL postings for these lines
                $table[$key][] = $row;                   // never seen it before
            }
        }

        // sort the table by the key; dr and cr accounts may be in an odd order
        ksort($table);

        // The table is an array of arrays of rows, so remove one level of indirection.
        $table2 = [];
        foreach ($table as $rows) {
            foreach ($rows as $row) {

                // we collected these to 8 places, but for the report we want 2
                foreach ($numericFields as $field) {
                    if (isset($row[$field])) {
                        $row[$field] = round((float)$row[$field], 2);
                    }
                }

                // Give a note saying we should run MIV or CSTools if there is costing and it differs from the GL
                if (($row['NOTES'] ?? '') == '') {
                    $valuationDiffDr = (($row['VALUATION_DEBIT']  ?? 0.00) != 0.00) ? ($row['ACCOUNT_VALUATION_DR_DIFF'] ?? 0.00) : 0.00;
                    $valuationDiffCr = (($row['VALUATION_CREDIT'] ?? 0.00) != 0.00) ? ($row['ACCOUNT_VALUATION_CR_DIFF'] ?? 0.00) : 0.00;

                    // abs() behaves oddly, so....
                    if ((($valuationDiffDr >= 1.0) || ($valuationDiffDr <= -1.0)) || (($valuationDiffCr >= 1.0) || ($valuationDiffCr <= -1.0))) {
                        $addNote($row, "Run MIV");
                    }
                }

                $table2[] = $row;
            }
        }
        return $table2;
    }


    /**
     *  Landed Costs - report on the landed costs in the system
     *
     * @param array  $params            user entered prams (date, item, wh, ...) if any
     *
     * @return array|false
     */
    private function landedCosts($params)
    {
        $ok = ($this->cacheLocations() && $this->cacheLandedCosts($params));
        if (!$ok) {
            return false;
        }

        $summedFields = ['LANDED_COST_AMOUNT', 'TARGET', 'ADJUSTMENT', 'QUANTITY'];
        $gmt          = new DateTimeZone("GMT");

        // Let's make a table of what we want....
        $table = [];

        foreach ($this->landedCosts as $transaction) {

            $locationRecord                = $this->locations->getByKey('RECORD#', $transaction['LOCATION#']);
            $transaction['LOCATION']       = $locationRecord['LOCATION'] ?? '';

            // Collect the fields for the report
            $key = 'K';
            $row = [];
            foreach ($transaction as $field => $value) {
                // skip fields we don't need in the result
                if (($field === 'LOCATION#') || ($field === 'DOCPARID') || ($field === InvCache::NameOfRowField)) {
                    continue;
                }
                $isSummed    = in_array($field, $summedFields);
                $row[$field] = $value ?? ($isSummed ? 0.0 : '');

                // don't add numeric fields to the key, as we will combine those....
                if ($isSummed) {
                    continue;
                }

                // The date is in a bad format for sorting....
                if ($field === 'DOCUMENT_DATE') {
                    // go from M/D/Y to Y/M/D do it sorts properly
                    $theDate = DateTime::createFromFormat('m/d/Y', $value, $gmt);
                    $value   = $theDate->format('Y-m-d');
                }
                $value = str_replace(' ', '~', $value);  // help the sort.  So '1' comes before '1 HAMMER'
                $key  .= $value . ' ';
            }

            // have we seen this before, less the amounts? Summarize
            if (isset($table[$key])) {
                foreach ($summedFields as $field) {
                    $table[$key][$field] = round($table[$key][$field] + $row[$field],  2);
                }
            } else {
                $table[$key]           = $row;        // never seen it before
            }
        }

        // sort the table by the key
        ksort($table);

        // and then remove the key
        $table = array_values($table);

        return $table;
    }


    /**
     *      List the transactions in the order the valuation report (itmhistcost) sees them
     *  and report on their 'average cost' at that moment, so one can see why the average
     *  does not match the details.
     *
     * @param array     $params         user entered prams (date, item, wh, ...) if any
     *
     * @return array|false
     */
    private function valuationSummaryValue($params)
    {
        // **** HELPERS ****

        $qvInfo = [];       // maintained by $collectQvsV()

        /** @var callable $collectQvsV */
        $collectQvsV = function($cost, $key, $sysGen) use (&$qvInfo) {
            // We get here if the current cost record is V-only.
            // $key is the row in the report so we can filter these later

            $recordNumber = $cost['RECORD#'];
            $adjusts      = ($cost['ADJDOCENTRYCOSTKEY'] ?? 0);

            if (($adjusts != 0) && isset($qvInfo[$adjusts])) {
                unset($qvInfo[$adjusts]);   // no longer a concern
                return;                     // so no need to save this record
            }

            // We care about SYSTEMGENERATED V layers that are not adjusted (meaning a 'Q' only txn with no adjustment)
            // and non-SYSTEMGENERATED V layers that do NOT adjust another (a standalone V)
            // save those that DO adjust so we can later find the SYSTEMGENERATED layer they affect, if possible
            $qvInfo[$recordNumber] = ['KEY' => $key, 'SYSGEN' => $sysGen, 'ADJUSTS' => $adjusts];
        };

        /** @var callable $cleanUpQvsV */
        $cleanUpQvsV = function( &$table, $yes ) use (&$qvInfo) {
            // find adjustments from one V layer to another.
            // when we're done all that is left is UN-ADJUSTED V layers
            foreach ($qvInfo as $recordNumber => $row) {
                $adjusts = $row['ADJUSTS'];
                if (($adjusts != 0) && isset($qvInfo[$adjusts])) {
                    unset($qvInfo[$adjusts]);       // no longer a concern
                    unset($qvInfo[$recordNumber]);  // nor is this current adjustment
                }
            }

            // now we want to update the table with the rows remaining from above....
            foreach ($qvInfo as $row) {
                $key = $row['KEY'];
                if (isset($table[$key])) {  // SHOULD be there, but....
                    $table[$key]['UNMATCHED'] = $yes;
                }
            }
        };


        // **** MAIN CODE ****
        $itmHistCostParams = $params;
        $itmHistCostParams['STARTDATE'] = '2000/01/01'; // reach back further than the report
        $ok = ($this->cacheItems() && $this->cacheItmHistCost($itmHistCostParams) && $this->cacheCosting($params));
        if (!$ok) {
            return false;
        }

        $docentries = [];
        // look at the docentrycost records, extract the docentry record numbers
        foreach ($this->transactionCosts as $row) {
            $recordNo = $row['DOCENTRYKEY'];
            $docentries[$recordNo] = true; // remove dups
        }

        // get the transactions for the UNSEEN docentrys...
        if ($this->cacheDocHdrsFromList(array_keys($docentries)) === false) {
            return false;
        }

        $gmt      = new DateTimeZone("GMT");
        $debit    = GT($this->translatedText, 'IA.DEBIT');
        $credit   = GT($this->translatedText, 'IA.CREDIT');


        // For average cost items, do we cost on IN, then OUT (the default),
        // or on when-entered (the docentry record# is our approximation for this)
        $result = QueryResult(["SELECT value FROM modulepref WHERE cny# = :1 AND property = 'AVGCOSTSEQUENCE'", GetMyCompany()]);
        if ($result === false) {
            return false;
        }
        $averageOption = 'P';
        if (!empty($result)) {
            $averageOption = $result[0]['VALUE'];
        }

        $table = [];
        $itemCostMethod  = [];
        $minDateByItemWh = [];
        $qtysLeft        = [];

        foreach ($this->selectDocHdrs as $transaction) {
            $docentrykey = $transaction['DEREC'];
            $costs       = $this->transactionCosts->getByKey('DOCENTRYKEY', $docentrykey);
            foreach ($costs as $cost) {

                $item    = $cost['ITEMKEY'];
                if (!isset($itemCostMethod[$item])) {
                    $itemRec    = $this->items->getByKey('ITEM', $item);
                    $itemCostMethod[$item] = $itemRec['COST_METHOD'];
                }
                $averageCost = ($itemCostMethod[$item] === 'A');
                $wh          = $cost['WHSEKEY'];
                $io          = $cost['IN_OUT'];    // cleverly, I sorts before O
                // go from M/D/Y to Y/M/D do it sorts properly
                $theDate = DateTime::createFromFormat('m/d/Y', $cost['DATEIN'], $gmt);
                $when    = $theDate->format('Y-m-d');

                // keep track of the EARLIEST record seen
                $earliest = $minDateByItemWh[$item][$wh] ?? '9999-99-99';
                if ($when < $earliest) {
                    $minDateByItemWh[$item][$wh] = $when;
                }

                if ($averageCost && ($averageOption == 'R')) {
                    $key = "~$item ~$wh ~$when~$docentrykey~$io~";   // docentry order; trailing squiggle is important, spaces are important
                } else {
                    $key = "~$item ~$wh ~$when~$io~$docentrykey";   // ins before outs
                }
                $in        = ($io === 'I');
                $sysGen    = (($cost['SYSTEMGENERATED'] ?? 'F') === 'T');
                $valueOnly = ($cost['AFFECTS_INVENTORY'] === 'V');
                $qtyOnly   = ($cost['AFFECTS_INVENTORY'] === 'Q');

                // If this is a Value layer and not part of a kit build,
                //     track it to see if it is 'dangling'
                if ($valueOnly && ($cost['ISAKIT'] === 'F')) {
                    $collectQvsV($cost, $key, $sysGen);
                }

                $qtyonhand = 0.0;
                $quantity  = 0.0;
                $value     = 0.0;
                if ( ! $valueOnly) {
                    $qtyonhand = $cost['QUANTITY'];
                }
                // value-only system layer doesn't count; looks for subsequent V invoice
                if ( ! $qtyOnly) {
                    $value    = $cost['CONTRIBUTEDCOST'];   // or 'COST' if we don't keep adjustments
                    if ( ! ($valueOnly && $sysGen)) {       // don't double-count system-generated V layers' quantity
                        $quantity = $cost['QUANTITY'];
                    }
                }

                // start to track quantities left
                $iw = "~$item ~$wh ~";
                $qtysLeft[$in][$iw][$key] = ibcadd(($qtysLeft[$in][$iw][$key] ?? 0), $qtyonhand, 8, true);

                if ( ! $in) {
                    // we track outbound as negative numbers so it is more Excel friendly
                    $quantity  = - $quantity;
                    $qtyonhand = - $qtyonhand;
                    $value     = - $value;
                }

                // remember these are i18n token names, like 'IA.WAREHOUSE' or 'IA.DOCUMENT_DATE'....
                $row = ['ITEM'                  => $item,
                        'WAREHOUSE'             => $wh,
                        'DEBIT_OR_CREDIT'       => $in ? $debit : $credit,
                        'DOCUMENT_DATE'         => $when,
                        'CREATION_DATE'         => $transaction['CREATION_DATE'],
                        'DOCUMENT_NAME'         => $transaction['DOCUMENT_NAME'],
                        'COST_METHOD'           => $itemCostMethod[$item],
                        'QUANTITY'              => $qtyonhand,
                        'QUANTITY_WITH_VALUE'   => $quantity,
                        'UNIT_COST'             => ($quantity != 0) ? ibcdiv($value, $quantity, 8, true) : 0,
                        'COST'                  => $value,
                        'QUANTITY_REMAINING'    => $in ? $qtyonhand : ' ',
                        'UNMATCHED'             => '',
                       ];
                if (isset($table[$key])) {
                    $table[$key]['QUANTITY']            = ibcadd($table[$key]['QUANTITY'] , $qtyonhand, 8, true);
                    $table[$key]['QUANTITY_WITH_VALUE'] = ibcadd($table[$key]['QUANTITY_WITH_VALUE'] , $quantity, 8, true);
                    $table[$key]['COST']                = ibcadd($table[$key]['COST']     , $value,    8, true);
                    $quantity                           = $table[$key]['QUANTITY_WITH_VALUE'];
                    $value                              = $table[$key]['COST'];
                    $table[$key]['UNIT_COST']           = ($quantity != 0) ? ibcdiv($value, $quantity, 8, true) : 0;
                } else {
                    $table[$key] = $row;
                }
            }
        }

        // track dangling Q and V layers
        $yes = GT($this->translatedText, 'IA.YES');
        $cleanUpQvsV($table, $yes);

        ksort($table); // sort by key

        // now wrap up the Quantity Left numbers
        // loop through the INBOUNDS, and subtract OUTBOUNDS
        if (isset($qtysLeft[true])) {
            foreach ($qtysLeft[true] as $iw => $tableRows) {      // true is IN, false is OUT....
                if (isset($qtysLeft[false][$iw])) {
                    foreach ($tableRows as $inKey => $qtyLeft) {
                        foreach ($qtysLeft[false][$iw] as $outKey => $outQty) {
                            if ($qtyLeft < $outQty) {
                                $qtysLeft[false][$iw][$outKey] = ibcsub($outQty, $qtyLeft, 8, true);
                                $qtyLeft = 0;
                            } else {   // qty left >= out Qty
                                $qtyLeft = ibcsub($qtyLeft, $outQty, 8, true);
                                unset($qtysLeft[false][$iw][$outKey]);  // remove the outbound record to save time on the next pass
                            }
                            if ($qtyLeft == 0) {
                                break;
                            }
                        }
                        $table[$inKey]['QUANTITY_REMAINING'] = $qtyLeft ?: ' '; // maybe reduce on hand, maybe to zero (empty)
                    }
                }
            }
        }

        // Time to finish up the running balances (the 'average cost')
        // Now find the starting balances.  These are also in item/wh/date order....
        // (if there was a date range, we want to know the starting balances before the date range)
        $foundStart  = [];
        foreach ($this->itmhistcost as $row) {
            $item = $row['ITEMKEY'];
            $wh   = $row['WHSEKEY'];
            $when = $row['SORTABLEDATE'];

            // do we even need this record?
            $earliestTransactionDate = $minDateByItemWh[$item][$wh] ?? null;
            if ($earliestTransactionDate === null) {
                continue; // don't need this one
            }

            // Is the date of this row less than the start of the transaction stream?
            // But is it the most recent one seen (i.e. CLOSEST to the start)?
            if (($when < $earliestTransactionDate) &&
                (($foundStart[$item][$wh]['SORTABLEDATE'] ?? '0000-00-00') < $when)) {
                $foundStart[$item][$wh] = $row;
            }
        }

        $startEntity = ['ON_HAND'        => 0.0,
                        'QTY_WITH_VALUE' => 0.0,
                        'EXTENDED_COST'  => 0.0,
                        'AVERAGE_COST'   => 0.0];
        $entry  = $startEntity; // fix inspection issue

        // now one last pass across the table to set the running balances,
        // the number reported by the valuation report under 'summary'
        $prevWh      = '';
        $prevItem    = '';
        foreach ($table as $index => $row) {
            $item = $row['ITEM'];
            $wh   = $row['WAREHOUSE'];
            if (($item !== $prevItem) || ($wh !== $prevWh)) {

                // what is the starting balance?
                $entry  = $startEntity;    // start with zeroes, unless we have a saved start value
                $ihc    = $foundStart[$item][$wh] ?? null;
                if ($ihc !== null) {
                    $entry = ['ON_HAND'         => $ihc['QTYONHAND'],
                              'QTY_WITH_VALUE'  => $ihc['QTYWITHVALUE'],
                              'EXTENDED_COST'   => $ihc['EXTENDEDCOST'],
                              'AVERAGE_COST'    => $ihc['COST']];
                }

                $prevItem = $item;
                $prevWh   = $wh;
            }
            // now add to the running totals
            $entry['ON_HAND']               = ibcadd($entry['ON_HAND'],        $row['QUANTITY'], 8, true);
            $entry['QTY_WITH_VALUE']        = ibcadd($entry['QTY_WITH_VALUE'], $row['QUANTITY_WITH_VALUE'], 8, true);
            $entry['EXTENDED_COST']         = ibcadd($entry['EXTENDED_COST'],  $row['COST'], 8, true);
            $entry['AVERAGE_COST']          = ($entry['QTY_WITH_VALUE'] == 0) ? 0.0
                                            : ibcdiv($entry['EXTENDED_COST'], $entry['QTY_WITH_VALUE'], 8, true);

            $table[$index] = array_merge($row, $entry);
        }

        // and remove the key
        $table = array_values($table);

        return $table;
    }


    /**
     *      Show the open periods by location
     *
     * @return array|false
     */
    private function openPeriods()
    {
        $ok = ($this->cacheLocations());
        if (!$ok) {
            return false;
        }

        // Step one: make an index of names
        $recordsName = [];
        foreach ($this->locations as $location) {
            $recordKey  = (int) $location['RECORD#'];
            $recordsName[$recordKey] = $location['LOCATION'] . '--' . $location['NAME'];
        }


        $table = [];

        foreach ($this->locations as $location) {
            $parentKey  = (int)($location['PARENTKEY'] ?? 0);
            $parentName = $recordsName[$parentKey] ?? '';
            $myName     = $location['LOCATION'] . '--' . $location['NAME'];
            $row = [
                'LOCATION'      => $myName,
                'OPEN_BOOKS'    => $location['OPEN_BOOKS'],
                'PARENT'        => $parentName,
            ];

            $table[$myName] = $row;
        }

        // sort and then remove the key
        ksort($table);
        $table = array_values($table);

        return $table;
    }


    /**
     *  Average Daily Costs - show the itmhistcost table
     *
     * @param array  $params
     *
     * @return array|false
     */
    private function averageDailyCosts($params)
    {
        $ok = ($this->cacheLocations() && $this->cacheItmHistCost($params));
        if (!$ok) {
            return false;
        }

        $table = [];
        $location  = '';
        foreach ($this->itmhistcost as $ihc) {
            $warehouse = $ihc['WHSEKEY'];
            $item      = $ihc['ITEMKEY'];
            $whseRec   = $this->warehouses->getByKey('WAREHOUSE', $warehouse);
            if ($whseRec) {
                $locationRec = $whseRec['LOCATIONREFKEY'] ?? 0;
                $locationRec = $this->locations->getByKey('RECORD#', $locationRec);
                $location    = $locationRec['LOCATION'] ?? '';
            }

            $itemRec    = $this->items->getByKey('ITEM', $item);
            $glGroup    = $this->glGroup($itemRec['GL_GROUP'] ?? 0);
            $costMethod = $itemRec['COST_METHOD'] ?? '';

            $row = [
                'ITEM'                  => $item,
                'WAREHOUSE'             => $warehouse,
                'DATE'                  => $ihc['ASON'],
                'ON_HAND'               => $ihc['QTYONHAND'],
                'QUANTITY_WITH_VALUE'   => $ihc['QTYWITHVALUE'],
                'UNIT_COST'             => round($ihc['COST'], 8),
                'EXTENDED_COST'         => round($ihc['EXTENDEDCOST'], 8),
                'LOCATION'              => $location,
                'GL_GROUP'              => $glGroup,
                'COST_METHOD'           => $costMethod,
            ];
            $key = 'K' . $item . ' ~ ' . $warehouse . ' ~ ' . $ihc['SORTABLEDATE'];
            $table[$key] = $row;
        }

        ksort($table);

        return array_values($table);
    }


    /**
     *  What transactions were NOT created by inventory?
     *
     * @param string    $name       report name
     * @param array     $params     any user parameters like date, location, ....
     *
     * @return array|false
     */
    private function transactionsOtherThanInventory($name, $params)
    {
        // *****************
        // **** HELPERS ****
        // *****************

        $priorLocation = ['RECORD#' => ''];    // one-location cache for this helper:

        /** @var callable $getLocation  get the location name from the record# */
        $getLocation = function(&$transaction, &$priorLocation) {
            $locationRecord = $transaction['LOCATION#'];
            if ($priorLocation['RECORD#'] != $locationRecord) {
                $priorLocation = $this->locations->getByKey('RECORD#', $locationRecord);
            }
            $transaction['LOCATION'] = $priorLocation['LOCATION'];
        };

        // *******************
        // **** MAIN CODE ****
        // *******************

        $order = [
            'GLAccountNonInventoryDetail'    => ['ACCOUNT', 'LOCATION', 'CURRENCY', 'MODULEKEY', 'SYMBOL', 'DEBIT', 'CREDIT', 'BATCH_DATE', 'BATCH_TITLE'],
            'GLAccountNonInventorySummary'   => ['ACCOUNT', 'LOCATION', 'CURRENCY', 'MODULEKEY', 'SYMBOL', 'DEBIT', 'CREDIT'],
        ];

        $ok = ($this->cacheGLAccts() && $this->cacheLocations() && $this->cacheGLAcctsWithNoInventory($params));
        if (!$ok) {
            return false;
        }

        // Let's make a table of what we want....
        $table = [];

        // ba.batch_title, ba.batch_date, ba.location, ba.journal#, gl.currency, gl.basecurr, al.amount, gl.tr_type, gl.account#
        foreach ($this->transactionsNotOurs as $transaction) {
            // Get the account, assign to DR or CR based on the TR_TYPE
            $isDebit     = ($transaction['TR_TYPE'] == 1); // -1 is credit
            $account     = $this->glAccounts->getByKey('RECORD#', $transaction['ACCOUNT#']);
            $accountName = ($account['ACCT_NO'] ?? '??') . '--' . ($account['TITLE'] ?? '??');
            $amount      = $transaction['AMOUNT'] ?? 0.00;
            $transaction['CREDIT']          = $isDebit ? 0 : (float)$amount;
            $transaction['DEBIT']           = $isDebit ? (float)$amount : 0;
            $transaction['ACCOUNT']         = $accountName;

            $getLocation($transaction,$priorLocation);

            // Collect the fields for the report
            $key  = 'K'; // force alpha, not numeric-as-alpha
            $row = [];
            foreach ($order[$name] as $field) {
                $isNumeric      = (($field === 'DEBIT') || ($field === 'CREDIT'));
                $value          = $transaction[$field] ?? ($isNumeric ? 0 : '');
                $row[$field]    = $value;
                // they key does not include the amounts so we can summarize them
                if ( ! $isNumeric) {
                    $value = str_replace(' ', '~', $value);  // help the sort.  So '1' comes before '1 HAMMER'
                    $key  .= $value . ' ';
                }
            }

            // have we seen this before, less the amounts? Summarize
            if (isset($table[$key])) {
                $table[$key]['DEBIT']  = round($table[$key]['DEBIT']  + $row['DEBIT'],  2);
                $table[$key]['CREDIT'] = round($table[$key]['CREDIT'] + $row['CREDIT'], 2);
            } else {
                $table[$key]           = $row;        // never seen it before
            }
        }

        // sort the table by the key
        ksort($table);

        // and then remove the key
        $table = array_values($table);

        return $table;
    }


//  ****************************************************************************
//  ****************************************************************************
//
//  Useful Caches
//
//  ****************************************************************************
//  ****************************************************************************



    /**
     * @param string[]      $params         parameters, if any
     *
     * @return bool                         sql ok?
     */
    private function cacheItmHistCost($params)
    {
        if (isset($this->itmhistcost)) {
            return true;
        }

        $this->itmhistcost = new InvCache();
        $this->itmhistcost->defineKey('ITEMKEY', false); // false -> not unique

        // set the params meta-fields
        $params['LOCATION_FIELD'] = '';         // No location field in this table, but we do use location for warehouses below
        $params['ITEM_REC_FIELD'] = '';
        $params['ITEM_ID_FIELD']  = 'itemkey';
        $params['WHSE_ID_FIELD']  = 'whsekey';  // but warehouses are per location, so we WANT to restrict by location
        $params['DATE_FIELD']     = 'ason';

        $whereParams    = '';
        $query          = [];
        $query[]        = "select goes here";
        $query[]        = GetMyCompany();
        $this->paramsToSql($params, $whereParams, $query, $parentLocations);

        $query[0] = "SELECT itemkey, whsekey, ason, cost, qtyonhand, qtywithvalue, extendedcost, to_char(ason,'YYYY-MM-DD') sortableDate
                      FROM itmhistcost 
                     WHERE CNY# = :1 
                           $whereParams 
                     ORDER BY itemkey, whsekey, sortableDate";
        $ok      = $this->itmhistcost->QueryResult($query);
        return $ok;
    }


    /**
     *  Given a DocumentManager document, get the docentrycost records for it
     *
     * @param array     $document       A document manager document, as you'd find in DocumentFormEditor
     *
     * @return bool                     ok?
     */
    private function cacheDocentrycostsFromDocument($document)
    {
        if (isset($this->docentrycosts)) {
            return true;
        }
        $docentryRecordNumbers      = [];
        $docentryLineByRecordNumber = [];

        $docentries = $document['ENTRIES'] ?? [];
        foreach ($docentries as $index => $docentry) {
            $recordNumber = $docentry['RECORDNO'] ?? ($docentry['RECORD#'] ?? 0);
            if ($recordNumber) {
                $docentryRecordNumbers[]                   = $recordNumber;
                $docentryLineByRecordNumber[$recordNumber] = $index + 1;
            }
        }

        $ok = true;
        $this->docentrycosts = new InvCache();
        if ( ! empty($docentryRecordNumbers)) {
            $query   = [];
            $query[] = "SELECT * from docentrycost where CNY# = :1 ";
            $query[] = GetMyCompany();
            $query   = PrepINClauseStmt($query, $docentryRecordNumbers, ' and docentrykey ');
            $ok      = $this->docentrycosts->QueryResult($query, function ($record, $docentryLineByRecordNumber) {
                $recordNumber     = $record['DOCENTRYKEY'];
                $record['LINENO'] = $docentryLineByRecordNumber[$recordNumber];   // save the original line number
                $record['FROMLINENO'] = $record['LINENO'];
                return $record;
            }, $docentryLineByRecordNumber);
        }
        return $ok;
    }


    /**
     * The cache of all item gl groups
     *
     * @return bool
     */
    private function cacheGLGroups()
    {
        if ($this->glGroups !== null) {
            return true;
        }
        $this->glGroups = new InvCache();

        $this->glGroups->defineKey('RECORD#');

        $qry   = [];
        $qry[] = "SELECT record#, name as gl_group FROM icitemglgrpmst WHERE cny# = :1 ORDER BY gl_group";
        $qry[] = GetMyCompany();

        $ok   = $this->glGroups->QueryResult($qry);
        $none = GT($this->translatedText, 'IA.NONE');
        $this->glGroups->add(['RECORD#' => 0, 'GL_GROUP' => $none]);    // not everything HAS a gl group!
        return $ok;
    }


    /**
     *  Get a cache of warehouses
     *
     * @return bool
     *
     */
    private function cacheWarehouses()
    {
        if ($this->warehouses !== null) {
            return true;
        }

        $this->warehouses = new InvCache();

        $this->warehouses->defineKey('RECORD#');
        $this->warehouses->defineKey('WAREHOUSE');    // the 'as' name, not LOCATION_NO

        $qry   = [];
        $qry[] = "SELECT record#, location_no as WAREHOUSE, locationrefkey, name
                    FROM icwarehousemst
                    WHERE cny# = :1 ";
        $qry[] = GetMyCompany();

        return $this->warehouses->QueryResult($qry);

    }


    /**
     * The cache of all items that are kits, stockable kits, or inventory items
     *
     * @return bool
     */
    private function cacheItems()
    {
        if ($this->items !== null) {
            return true;
        }

        $this->items = new InvCache();

        $this->items->defineKey('RECORD#');
        $this->items->defineKey('ITEM');    // the 'as' name, not ITEMID

        $qry   = [];
        $qry[] = "SELECT record#, itemid as item, productlinekey as productline_id, cost_method, glgrpkey as gl_group, itemtype as item_type,
                        revposting, enablesno, enablelot, enablebin, enableexpiration
                    FROM icitemmst 
                    WHERE cny# = :1 -- AND itemtype in ('I', 'K', 'SK')
                    ORDER BY itemid";
        $qry[] = GetMyCompany();

        return $this->items->QueryResult($qry);
    }


    /**
     *  cache the preferences by module (OE, PO, INV)
     */
    /* NOT NEEDED YET...
    private function cachePreferences()
    {
        if ($this->preferences !== null) {
            return;
        }

        global $kINVid, $kPOid, $kSOid;
        $this->preferences = [];
        GetModulePreferences($kINVid, $this->preferences['INV']);
        GetModulePreferences($kPOid,  $this->preferences['PO']);
        GetModulePreferences($kSOid,  $this->preferences['OE']);
    }
    ******************* */

    /**
     *  cache the TDs for OE, PO, and INV
     *
     * @param bool $onlyCurrent         only current docpars?
     *
     * @return bool
     */
    private function cacheTDs($onlyCurrent)
    {
        if ($this->docpar !== null) {
            return true;
        }

        // Get the total for ONHAND
        $qry   = [];
        $qry[] = "SELECT record#, name
                    FROM ictotal 
                    WHERE cny# = :1  ";
        $qry[] = GetMyCompany();
        $result = QueryResult($qry);    // NOT a cached query
        if ($result === false) {
            return false;
        }
        $keyToName = [];
        foreach ($result as $row) {
            $keyToName[ $row['RECORD#']] = $row['NAME'];  // like ONHAND, ONHOLD, ...
        }

        // Get the totals for each docpar
        $qry   = [];
        $qry[] = "SELECT docparkey, Q_QV, sign, totalkey
                    FROM docpartotalsmst 
                    WHERE cny# = :1 
                    ORDER BY docparkey";
        $qry[] = GetMyCompany();
        $result = QueryResult($qry);    // NOT a cached query
        if ($result === false) {
            return false;
        }
        // IA.ON_HAND ?

        $docparTotals = [];
        foreach ($result as $row) {
            $name   = $keyToName[ $row['TOTALKEY']];
            $sign   = (($row['SIGN'] ?? 1) == 1) ? '+' : '-';
            $effect = $name . ':' . $sign . ($row['Q_QV'] ?? '?');
            if (isset($docparTotals[$row['DOCPARKEY']])) {
                $docparTotals[$row['DOCPARKEY']] .= ',' . $effect;   // collect a list of them
            } else {
                $docparTotals[$row['DOCPARKEY']] = $effect;
            }
        }

        // get the customer/vendor gl group (also called entityglgroup)
        $qry   = [];
        $qry[] = "SELECT record#, name
                    FROM entityglgrp 
                    WHERE cny# = :1 ";
        $qry[] = GetMyCompany();
        $result = QueryResult($qry);    // NOT a cached query
        if ($result === false) {
            return false;
        }

        $customerGLGroupKeyToName = [];
        foreach ($result as $row) {
            $customerGLGroupKeyToName[$row['RECORD#']] = $row['NAME'];
        }

        // now get the GL entries for each docpar
        $qry   = [];
        $qry[] = "SELECT record#, nvl(itemgrpkey,0) as gl_groupkey, nvl(entgrpkey,0) as customer_groupkey, nvl(glaccountrecordno,0) as gl_accountkey, dr_cr, module, line_no, docparkey
                    FROM offsetacct
                    WHERE cny# = :1 AND module = 'INV'
                    ORDER BY line_no, dr_cr";
        $qry[] = GetMyCompany();
        $result = QueryIterable($qry);    // NOT a cached query, but an iterator nonetheless
        if ($result === false) {
            return false;
        }

        $docparLookup = [];
        foreach ($result as $row) {
            $customerGLKey = $row['CUSTOMER_GROUPKEY'];
            $row['CUSTOMER_GL_GROUP'] = $customerGLGroupKeyToName[$customerGLKey] ?? '';  // often will be zero/empty
            $docparLookup[$row['DOCPARKEY']][] = $row;
        }
        $result->close();
        unset($result);

        $qry   = [];
        // note: in_out is 'D' or 'I' for decrease/increase
        // latestversionkey is null for the latest version
        $latest = $onlyCurrent ? 'and latestversionkey is null' : '';
        $qry[] = "SELECT record#, docid, docclass, category, in_out, sale_pur_trans, updinv, updgl, 
                         cust_vend, latestversionkey, to_char(whencreated, 'MM/DD/YYYY') as whencreated
                    FROM docparmst 
                    WHERE cny# = :1  and status = 'T'  $latest
                    ORDER BY docid";
        $qry[] = GetMyCompany();

        $this->docparGLs = [];
        $this->docpar = new InvCache();
        $this->docpar->defineKey('RECORD#');
        $this->docpar->defineKey('DOCID', false);

        $ok = $this->docpar->QueryResult($qry, function($docpar, $docparStuff) {
            $recordNo     = $docpar['RECORD#'];
            $docpar['GL'] = $docparStuff['GL'][$recordNo] ?? [];
            foreach ($docpar['GL'] as $index => $gl) {
                $this->docparGLs[$gl['GL_GROUPKEY'] ?? 0][] = ['DOCPARKEY' => $recordNo, 'GLINDEX' => $index];
            }

            $docpar['EFFECT'] = $docparStuff['EFFECT'][$recordNo] ?? ''; // ONHAND effects

            return $docpar;
        }, ['GL' => $docparLookup, 'EFFECT' => $docparTotals] );
        return $ok;
    }


    /**
     *  Cache the gl accounts
     *
     * @return bool
     *
     */
    private function cacheGLAccts()
    {
        if ($this->glAccounts !== null) {
            return true;
        }

        $this->glAccounts = new InvCache();
        $this->glAccounts->defineKey('ACCT_NO');
        $this->glAccounts->defineKey('RECORD#');

        $qry   = [];
        $qry[] = "SELECT record#, acct_no, title, normal_balance
                    FROM baseaccountmst
                    WHERE cny# = :1 and statistical = 'F'
                    ORDER BY acct_no";
        $qry[] = GetMyCompany();

        return $this->glAccounts->QueryResult($qry);
    }


    /**
     *  Cache the locations
     *
     * @return bool
     *
     */
    private function cacheLocations()
    {
        if ($this->locations !== null) {
            return true;
        }

        $this->locations = new InvCache();
        $this->locations->defineKey('RECORD#');
        $this->locations->defineKey('LOCATION');

        $qry   = [];
        $qry[] = "SELECT record#, location_no as location, name, parentkey, startopen as OPEN_BOOKS
                    FROM locationmst
                    WHERE cny# = :1 ";
        $qry[] = GetMyCompany();

        return $this->locations->QueryResult($qry);
    }


    /**
     *  cache transactions that posted to the GL.  This will be SLLLOOOOWWWW
     *
     * @param array      $params    from the UI: specific date ranges or whatnot
     * @return bool
     */
    private function cacheGLTransactions($params)
    {
        if ($this->transactions !== null) {
            return true;
        }

        $qry    = [];
        $qry[0] = "select clause goes here";
        $qry[1] = GetMyCompany();

        if ($this->paramsToSql($params, $whereParams, $qry, $parentLocations) === false) {
            return false;
        }

        // transactions
        $this->transactions = new InvCache();

        // remember to try to use i18n friendly names, meaning if you put 'IA.' in front of it, it is translated
        $qry[0] = "SELECT to_char(dh.whencreated, 'MM/DD/YYYY') as document_date, to_char(dh.auwhencreated, 'MM/DD/YYYY') as creation_date, dh.docid as document_name, 
                            dh.docparid as document_type, dh.docparkey,
                            de.record# as derec, de.itemkey as deitem, de.warehousekey as warehouse,
                            de.quantity, r.amount as deglresolve_amount,
                            gl.currency, gl.basecurr as base_currency, gl.itemdimkey, gl.account#, gl.tr_type,
                            gl.location#, ba.batch_title, ba.batch_date
                    FROM deglresolve r, dochdrmst dh, docentrymst de, glentrymst gl, glbatchmst ba
                    WHERE r.cny# = :1 and dh.cny# = r.cny# and de.cny# = r.cny# and gl.cny# = r.cny# and ba.cny# = gl.cny#
                      AND gl.record# = r.glentrykey
                      AND dh.record# = r.dochdrkey
                      AND de.record# = r.docentrykey
                      AND ba.record# = gl.batch#
                      $whereParams ";

        // Get the transactions, this can be slow....
        if (empty($parents)) {
            return $this->transactions->QueryResult($qry);
        } else {
            return $this->transactions->QueryResult($qry, function ($row, $parents) {
                $location = $row['LOCATION#'];
                if (in_array($location, $parents)) {
                    $row['PARENT'] = true;
                }
                return $row;
            }, $parentLocations);
        }
    }


    /**
     *  cache dochdr records that contain the docentry records in the passed-in array of docentry record#s
     *
     * Unlike the other caches, you can call this more than once with different params and get a different result....
     *
     * @param int[]     $these      docentry record#s
     *
     * @return bool                 sql ok?
     */
    private function cacheDocHdrsFromList($these)
    {
        // anything to get?
        if (empty($these)) {
            return true;
        }

        $this->selectDocHdrs = new InvCache();
        $this->selectDocHdrs->defineKey('DOCENTRYKEY', false);

        $qry    = [];

        // remember to try to use i18n friendly names, meaning if you put 'IA.' in front of it, it is translated
        $qry[]  = "SELECT to_char(dh.whencreated, 'MM/DD/YYYY') as document_date, to_char(dh.auwhencreated, 'MM/DD/YYYY') as creation_date, dh.docid as document_name, 
                            dh.docparid as document_type, dh.docparkey, de.locationkey as location#, de.currency,
                            de.record# as derec, de.itemkey as item, de.warehousekey as warehouse, de.quantity, 
                            de.basecurr as base_currency, de.costmethod as cost_method
                    FROM dochdrmst dh, docentrymst de
                    WHERE dh.cny# = :1 and de.cny# = dh.cny#
                      AND dh.record# = de.dochdrkey ";
        $qry[]  = GetMyCompany();
        $qry    = PrepINClauseStmt($qry, $these, ' and de.record# ');
        $qry[0] .= " ORDER BY de.record# ";

        // Get the dochdrs, this can be slow....
        return $this->selectDocHdrs->QueryResult($qry);
    }


    /**
     *  cache docentrycost records
     *
     * @param string[]  $params     user params
     *
     * @return bool                 sql ok?
     */
    private function cacheCosting($params)
    {
        if ($this->transactionCosts !== null) {
            return true;
        }
        $this->decSeen = [];

        $this->transactionCosts = new InvCache();
        $this->transactionCosts->defineKey('DOCENTRYKEY', false);

        // set the params meta-fields
        $params['LOCATION_FIELD'] = '';         // No location field in this table, but we do use location for warehouses below
        $params['ITEM_REC_FIELD'] = '';
        $params['ITEM_ID_FIELD']  = '';
        $params['WHSE_ID_FIELD']  = 'dec.whsekey';
        $params['DATE_FIELD']     = 'dec.datein';

        $qry    = [];
        $qry[0] = "select clause goes here";
        $qry[1] = GetMyCompany();
        if ($this->paramsToSql($params, $whereParams, $qry, $parentLocations) === false) {
            return false;
        }

        // for stockable kits we need to search both in the docentry and docentrycostkits
        $decWhereParams = $whereParams;
        $itemID         = trim($params['ITEM'] ?? '');
        if ($itemID != '') {
            $count           = count($qry);
            $whereParams    .= " AND  dec.itemkey = :$count";
            $decWhereParams .= " AND ((de.itemkey = :$count) OR (dec.itemkey = :$count)) ";
            $qry[]           = $itemID;
        }

        $parents = [];
        foreach ($parentLocations as $parent) {
            $parents[$parent] = true;
        }

        $qry[0] = "SELECT *
                      FROM   
                        (
                            SELECT dec.docentrykey, dec.itemkey, dec.whsekey, dec.in_out, dec.quantity, dec.qtyleft, dec.docentrycostkey, dec.datein,
                                    dec.serialno, dec.lotno, dec.binkey, dec.expirationdate, dec.affects_inventory, dec.cost, dec.unitcost, 
                                    dec.costmethod, dec.adjdocentrycostkey, dec.contributedqty, dec.contributedcost, dec.record#,
                                    dec.systemgenerated, 'F' as isakit
                            FROM    docentrycost dec
                            WHERE   cny# = :1 $whereParams
                        UNION ALL
                            SELECT dec.docentrykey, dec.itemkey, dec.whsekey, dec.in_out, dec.quantity, dec.qtyleft, dec.docentrycostkey, dec.datein,
                                    dec.serialno, dec.lotno, dec.binkey, dec.expirationdate, dec.affects_inventory, dec.cost, dec.unitcost, 
                                    dec.costmethod, null as adjdocentrycostkey, dec.quantity as contributedqty, dec.cost as contributedcost,
                                    dec.record#, 'F' as systemgenerated, 'T' as isakit
                            FROM    docentrycostkits dec, docentrymst de
                            WHERE   dec.cny# = :1 AND de.cny# = dec.cny# AND de.record# = dec.docentrykey
                                    $decWhereParams
                        )
                      ";

        // this makes a CPU time difference, as usually there are no parents...
        if (empty($parents)) {
            $ok = $this->transactionCosts->QueryResult($qry);
        } else {
            $ok = $this->transactionCosts->QueryResult($qry, function ($row, $parents) {
                $location = $row['LOCATION#'];
                if (isset($parents[$location])) {
                    $row['PARENT'] = true;  // only set it on the few that are parents to save ram/time
                }
                return $row;
            }, $parents);
        }

        return $ok;
    }


    /**
     *  If a TD is INBOUND, what is the inbound account?  if OUTBOUND, what is the outbound account?
     *
     *  This way we know where the Inventory Valuation is going
     *
     * @return array|false          The acounts or failure
     */
    private function accountsForInventoryValuation()
    {
        // what do we post to?  Those are the ones we care about....
        if ( ! $this->cacheTDs(true) || ! $this->cacheGLAccts()) {
            return false;
        }

        // collect the accounts we care about
        $accounts = [];
        foreach ($this->docpar as $docpar) {
            $in = (($docpar['IN_OUT'] ?? '') == 'I');
            if (strpos($docpar['EFFECT'], 'ONHAND') !== false) {  // do we affect ONHAND?  IA.ON_HAND??
                foreach ($docpar['GL'] as $gl) {
                    $dr   = (($gl['DR_CR'] ?? '0') == '1');
                    $keep = ($in === $dr);  // so inbound keeps DRs and outbound keeps CRs
                    if ($keep) {
                        $accountRec = $this->glAccounts->getByKey('ACCT_NO', $gl['GL_ACCOUNTKEY']);
                        $account = $accountRec['RECORD#'] ?? 0;
                        if ($account) {
                            $accounts[$account][$in] = true;   // want these, remember if we want in or out or both
                        }
                    }
                }
            }
        }
        return $accounts;
    }

    /**
     *  cache transactions that posted to the GL.  This will be SLLLOOOOWWWW
     *
     * @param array      $params    from the UI: specific date ranges or whatnot
     * @return bool
     */
    private function cacheGLAcctsWithNoInventory($params)
    {
        if ($this->transactionsNotOurs !== null) {
            return true;
        }

        // and init our cache
        $this->transactionsNotOurs = new InvCache();

        // decode the params:
        $whereParams = '';
        $params['LOCATION_FIELD'] = 'gl.location#';
        $params['ITEM_REC_FIELD'] = 'gl.itemdimkey';
        $params['ITEM_ID_FIELD']  = '';
        $params['WHSE_ID_FIELD']  = '';
        $params['DATE_FIELD']     = 'gl.entry_date';

        $qry    = [];
        $qry[0] = "select clause goes here";
        $qry[1] = GetMyCompany();
        if ($this->paramsToSql($params, $whereParams, $qry, $parentLocations) === false) {
            return false;
        }

        // collect the accounts we care about
        $accounts = $this->accountsForInventoryValuation();
        if ($accounts === false) {
            return false;
        }

        // These modules are from Inventory
        $notTheseModules = [ '7.INV', '8.SO', '9.PO' ];

        // Now get the stuff that isn't in cacheGLTransactions above.....

        // remember to try to use i18n friendly names, meaning if you put 'IA.' in front of it, it is translated
        $qry[0] = "SELECT  ba.batch_title, ba.batch_date, ba.modulekey, ba.journal#,
                          gl.location#, gl.currency, gl.basecurr, gl.amount, gl.tr_type, gl.account#,
                          bj.symbol, bj.title as booktitle
                    FROM  glentrymst gl, glbatchmst ba, basejournalmst bj
                    WHERE gl.cny# = :1 and ba.cny# = gl.cny# and ba.cny# = bj.cny#
                      AND ba.record# = gl.batch#
                      AND bj.record# = ba.journal#
                   $whereParams ";
        $qry   = PrepINClauseStmt($qry, array_keys($accounts),   ' and gl.account# ',false, 'account');  // record#s so no binding
        $qry   = PrepINClauseStmt($qry, $notTheseModules, ' and not ba.modulekey ', false, 'module', true);

        $ok = $this->transactionsNotOurs->QueryResult($qry);

        return $ok;
    }


    /**
     *  cache transactions that posted to the GL.  This will be SLLLOOOOWWWW
     *
     * @param array      $params    from the UI: specific date ranges or whatnot
     * @return bool
     */
    private function cacheLandedCosts($params)
    {
        if ($this->landedCosts !== NULL) {
            return true;
        }
        $this->landedCosts = new InvCache();

        // In order to find landed costs that don't refer to any adjusting transaction, we cannot use
        // the SCMMacro stuff, because there is no entry there.  Instead, we have to manually look for them.
        // Only problem is that those invoices can have different names, so we can't hardcode the docparid....
        $qry    = [];
        $qry[0] = "SELECT distinct dh.docparid
                    FROM  dochdrmst dh, scmmacroresolvemst s, scmmacrohdrmst sh
                    WHERE dh.cny# = :1 and s.cny# = dh.cny# and sh.cny# = s.cny#
                      AND s.scmmacrokey = sh.record#
                      AND sh.name IN ('Landed cost', 'LC Act and EstRev') -- get the right kind of macro
                      AND dh.record#    = s.sourcedockey
                    ";
        $qry[1] = GetMyCompany();
        $result = QueryResult($qry);
        if ($result === false) {
            return false;
        }

        // Are there any landed costs?
        if (empty($result)) {
            return true;
        }

        // Save the docpar ids for when we do the big search below....
        $landedCostDocPars = [];
        foreach ($result as $oneDocParID) {
            $landedCostDocPars[] = $oneDocParID['DOCPARID'];    // already unique....
        }

        // decode the params:
        $whereParams = '';
        $params['LOCATION_FIELD'] = 'det.locationkey';
        $params['ITEM_REC_FIELD'] = '';
        $params['ITEM_ID_FIELD']  = 'det.itemkey';
        $params['WHSE_ID_FIELD']  = 'det.warehousekey';
        $params['DATE_FIELD']     = 'dhs.whencreated';

        $qry    = [];
        $qry[0] = "select clause goes here";
        $qry[1] = GetMyCompany();
        if ($this->paramsToSql($params, $whereParams, $qry, $parentLocations) === false) {
            return false;
        }

        // remember to try to use i18n friendly names, meaning if you put 'IA.' in front of it, it is translated
        $qry[0] = "SELECT  to_char(dhs.whencreated, 'MM/DD/YYYY') as document_date,
                           dhs.docid as LANDED_COST_TRANSACTION, dht.docid as ADJUSTMENT_TRANSACTION, dha.docid as TARGET_TRANSACTION_ID,
                           des.value as LANDED_COST_AMOUNT, det.cost as ADJUSTMENT, dea.value as TARGET,
                           dea.itemkey as item, nvl(dea.warehousekey,'') as warehouse, dea.quantity, det.locationkey as location#, dhs.docparid

                    FROM   scmmacroresolvemst s, scmmacrohdrmst sh,
                           docentrymst dea, dochdrmst dha,  -- adjusting (Transfer In/Purchase)
                           docentrymst des, dochdrmst dhs,  -- Landed Cost Invoice
                           docentrymst det, dochdrmst dht   -- target (Adjustment)

                     WHERE s.cny#        = :1     and sh.cny#  = s.cny# 
                      AND  dea.cny#      = s.cny# and dha.cny# = dea.cny# and dea.dochdrkey = dha.record# 
                      AND  des.cny#      = s.cny# and dhs.cny# = dea.cny# and des.dochdrkey = dhs.record# 
                      AND  det.cny#      = s.cny# and dht.cny# = det.cny# and det.dochdrkey = dht.record#
                      AND  s.scmmacrokey = sh.record#
                      and sh.name IN ('Landed cost', 'LC Act and EstRev') -- get the right kind of macro
                      AND  dea.record#   = det.adjdocentrykey  -- the transaction being adjusted is pointed to by the adjustment
                      AND  det.record#   = s.targetdocentrykey -- and the macro points to the target (the adjustment)
                      AND  des.record#   = s.sourcedocentrykey -- and the source (the landed cost invoice)
                           $whereParams 
                   UNION ALL 
                       -- landed cost invoices without a target...
                     SELECT to_char(dhs.whencreated, 'MM/DD/YYYY') as document_date,
                            dhs.docid as LANDED_COST_TRANSACTION, '' as ADJUSTMENT_TRANSACTION, '' as TARGET_TRANSACTION_ID,
                            det.value as LANDED_COST_AMOUNT, 0 as ADJUSTMENT, 0 as TARGET,
                            det.itemkey as item, nvl(det.warehousekey,'') as warehouse, det.quantity, det.locationkey as location#, dhs.docparid
                      FROM  docentrymst det, dochdrmst dhs  -- note the det not des nonsense to make the whereParams work
                      WHERE det.cny# = :1 and dhs.cny# = det.cny#  
                        and det.dochdrkey = dhs.record# 
                            $whereParams
                        AND NOT EXISTS (
                            SELECT 1 FROM scmmacroresolvemst s WHERE s.cny# = dhs.cny# AND s.sourcedockey = dhs.record#
                        ) ";
        $qry = PrepINClauseStmt($qry, $landedCostDocPars, ' and dhs.docparid ');

        $ok = $this->landedCosts->QueryResult($qry);
        return $ok;
    }


    /**
     *  Graph Line Notes - any comments on the graph line
     *
     *      Include such things as
     *          - Q but no V, V but no Q
     *          - ONHOLD/ONORDER being doubled or lost
     *
     * At this time, the effects are recorded in this format: "(ONORDER:+QV)"
     *
     * @param string    $line           The text line about to be inserted into the graph
     *
     * @return string                   The notes, might be empty
     */
    private function graphLineNotes($line)
    {
        // parse the line, one effect at a time
        /** @var callable $getNextEffect */
        $getNextEffect = function($line, &$offset, &$effectKind, &$qv, &$isMinus ) {
            $effectKind = '';
            $qv = '';
            // we're looking for things like:
            // "(ONORDER:+QV)"
            // but watch out for docpar names with parens like:
            // "(Q only)"
            // find the next open paren
            $startEffect = strpos($line, '(', $offset);
            if ($startEffect === false) {
                return false;
            }
            // and then its matching close paren
            $endEffect = strpos($line,')', $startEffect);
            if ($endEffect === false) {
                return false;
            }
            $offset    = $endEffect+1;

            // take that string
            $effect = substr($line, $startEffect+1, ($endEffect - $startEffect) - 1);

            // does it have a colon and + or -?
            $plus  = strpos($effect, ':+');
            $minus = strpos($effect, ':-');

            // is this the '(Q only)' case?  i.e. not one of the effects strings?
            if (($plus === false) && ($minus === false)) {
                return true;
            }

            $isMinus = ($plus === false);

            // Get WHAT is the effect, like ONHAND or ONHOLD.  Do we need to worry about I18m here?  (yes, eventually!)
            $effectKind = substr($effect, 0, $isMinus ? $minus : $plus);

            // and get the Q, V, or QV value:
            $qv = substr($effect, ($isMinus ? $minus : $plus)+2);
            return true;
        };

        /** @var callable $message */
        $message = function($msgs, $addMessage) {
            if ($msgs != '') {
                $msgs .= '; ';
            }
            return $msgs . $addMessage;
        };


        // **** MAIN CODE *****

        $rtn    = '';
        $offset = 0;
        $kinds  = [];
        while ($getNextEffect($line,$offset,$effectKind,$qv, $isMinus )) {
            if ($effectKind !== '') {
                $one = $isMinus ? -1 : +1;
                $kinds[$effectKind][$qv] = ($kinds[$effectKind][$qv] ?? 0) + $one;

                // if ONHAND, we can 'undo' the most recent ONHOLD or ONORDER.
                // if not ONHAND, then the most recent ONHOLD or ONORDER needs to be refreshed....

            }
        }
        foreach ($kinds as $effectKind => $qvs) {
            $q = 0;
            $v = 0;
            foreach ($qvs as $qv => $quantity) {
                if (($qv === 'Q') || ($qv === 'QV')) {
                    $q += $quantity;
                }
                if (($qv === 'V') || ($qv === 'QV')) {
                    $v += $quantity;
                }
            }
            // now, finally, do the tests....
            if (($q > 1) || ($q < -1)) {
                $rtn = $message($rtn,"$effectKind Quantity imbalance");
            }
            if (($v > 1) || ($v < -1)) {
                $rtn = $message($rtn,"$effectKind Value imbalance");
            }
            if (($q !== 0) && ($v === 0)) {
                $rtn = $message($rtn, "$effectKind Quantity with no value");
            }
            else if (($q === 0) && ($v !== 0)) {
                $rtn = $message($rtn, "$effectKind Value with no quantity");
            }
        }
        return $rtn;
    }


    /**
     *      Not exactly a cache, but the document graph....
     *
     *
     * @return string|array
     */
    private function getDocumentGraph()
    {
        if (! $this->cacheTDs(true)) {
            return false;
        }

        // get a list of the docpar docids
        $docparids = [];
        foreach ($this->docpar as $row) {
            if (! isset($row['LATESTVERSIONKEY'])) {
                $docparids[$row['DOCID']] = $row['EFFECT'] ?? '';
            }
        }
        ksort($docparids);

        // Get the conversion graph
        $conversionManager = new ConversionManager(['mod' => 'inv']);
        $conversionManager->_mod = 'ALL'; // well, we want everything here.....
        $graph = $conversionManager->bulkConvertTo(array_keys($docparids));

        // add in the effect to the name, so 'Sales Txn (+QV)'
        foreach ($graph as $docparid => $oneDocPar) {
            $effect                     = $docparids[$docparid];
            $graph[$docparid]['EFFECT'] = ($effect != '') ? (' (' . $effect . ')') : '';
        }

        $table = [];

        // Walk the graph, starting with TD's that have no previous TD's
        // NOTE! WATCH OUT FOR LOOPS!  A-->B-->A or A-->A
        foreach ($graph as $docparid => $oneDocPar) {
            $sources = $oneDocPar['SOURCES'] ?? [];
            if (empty($sources)) {
                $line = $docparid . $oneDocPar['EFFECT'];
                $loopDetection = [$docparid];
                $this->followTargets($line, $docparid, $graph, $loopDetection, $table);
                if (count($table) > self::MAX_GRAPH_TABLE_SIZE) {
                    return $table;
                }
            }
        }

        // also, find docs that have no source or target TDs
        foreach ($docparids as $docparid => $effect) {
            if ( ! isset($graph[$docparid])) {
                if ($effect != '') {
                    $docparid .= ' (' . $effect . ')';
                }
                $table[] = ['DOCUMENT' => $docparid, 'NOTES' => $this->graphLineNotes($docparid) ];   // let the customer know there is nowhere to go
                if (count($table) > self::MAX_GRAPH_TABLE_SIZE) {
                    return $table;
                }
            }
        }

        return $table;
    }




    /**
     *  This recursive routine follows ONE target path to completion, resulting in a row of text
     *  that can go on the fulfillment paths grid.
     *
     * @param string    $line           The string for this path so far
     * @param string    $docparid       The docpar id
     * @param array     $graph          The whole graph of possibilities
     * @param array     &$loopDetection Are we in a loop?
     * @param string[]  &$table         The resulting table
     *
     */
    private function followTargets($line, $docparid, $graph, &$loopDetection, & $table)
    {
        $targets = $graph[$docparid]['TARGETS'] ?? [];
        if (empty($targets)) {
            $table[] = ['DOCUMENT' => $line, 'NOTES' => $this->graphLineNotes($line)];
        } else {
            foreach ($targets as $target) {
                $targetDocId = $target['DOCID'];
                $loop        = in_array( $targetDocId, $loopDetection );
                $line2       = $line . ' ----> ' . $targetDocId . $graph[$targetDocId]['EFFECT'];
                // not already seen, right?  You can make loops in TDs; let the loop show ONCE
                if ($loop) { // is this the beginning of the loop?
                    // yes, then it is the end of the line, as if there were no more targets
                    $table[] = ['DOCUMENT' => $line2, 'NOTES' => $this->graphLineNotes($line2)];
                    break;
                } else {
                    if (count($table) > self::MAX_GRAPH_TABLE_SIZE) {
                        return;
                    }
                    $loopDetection[] = $targetDocId; // loop detection
                    $this->followTargets($line2, $targetDocId, $graph, $loopDetection, $table);    // Curses!  He recurses!
                }
            }
        }
    }






//  ****************************************************************************
//  ****************************************************************************
//
//  Miscelanious Helper Routines
//
//  ****************************************************************************
//  ****************************************************************************

    /**
     *  Given a GL Group record number, fetch the name
     *
     * @param int   $recordNumber
     *
     * @return string
     */
    private function glGroup($recordNumber)
    {
        $groupName = '';
        if ($recordNumber != 0) {
            if ($this->glGroups === null) {
                if (!$this->cacheGLGroups()) {
                    return $groupName;
                }
            }
            $groupRecord = $this->glGroups->getByKey('RECORD#', $recordNumber);
            $groupName   = $groupRecord['GL_GROUP'] ?? '';
        }
        if ($groupName == '') {
            $groupName = GT($this->translatedText, 'IA.NONE');
        }
        return $groupName;
    }


    /**
     *  Given a location record number, find any children and other descendants.
     *  Return them in the $locationRecs array.
     *
     * @param int       $recordNumber       The record number to find kids for
     * @param int[]     $locationRecs       The running list of locations
     */
    private function locationChildren($recordNumber, &$locationRecs)
    {
        // Step one: make an index
        $recordKeysByParent = [];
        foreach ($this->locations as $location) {
            $parentKey  = (int)($location['PARENTKEY'] ?? 0);
            $recordKey  = (int) $location['RECORD#'];
            if ($parentKey) {
                if ( ! isset($recordKeysByParent[$parentKey])) {
                    $recordKeysByParent[$parentKey] = [];
                }
                $recordKeysByParent[$parentKey][] = $recordKey; // many kids, one parent
            }
        }

        // Step two: walk the index to get the children
        $fakeRecursion  = [ (int)$recordNumber ];  // use a stack instead
        while ( ! empty($fakeRecursion)) {
            $locationKey = array_pop($fakeRecursion) ?? 0;
            if ($locationKey) {
                $locationRecs[] = $locationKey;
                foreach ($recordKeysByParent[$locationKey] ?? [] as $kid) {
                    array_push($fakeRecursion, $kid);
                }
            }
        }
    }


    /**
     *  Given a location name, get it and all the records that are beneath it
     * AND all its parents, up the chain
     *
     *  Useful enough to make public
     *
     * @param string         $locationName
     * @param int[]          $parents           the parent locations, may be empty
     *
     * @return int[]                            the locations and sub-locations; may be empty
     */
    public function getLocations($locationName, &$parents)
    {
        static $locationCache = []; // assume we ask for the same location name a couple of times
        static $parentCache   = [];
        static $nameCached    = '';

        $locationName      = trim($locationName);
        $parents           = [];

        if ($locationName == '') {
            return [];
        }

        if (($nameCached !== $locationName) || empty($locationCache)) {
            $nameCached    = $locationName;
            $locationCache = [];
            $parentCache   = [];

            // well, wait, IS there a location?
            if ($locationName != '') {

                $locationRec = $this->locations->getByKey('LOCATION', $locationName);
                if ($locationRec === NULL) {
                    // todo: add error
                    throw new Exception("Location '$locationName' is not valid.");
                    // return [];
                }

                $recordNumber = $locationRec['RECORD#'] ?? 0;
                if ($recordNumber) {
                    $this->locationChildren($recordNumber, $locationCache);

                    // now get the parent chain too....
                    $parent = $locationRec['PARENTKEY'] ?? 0;
                    while ($parent) {
                        $parentCache[] = $parent;
                        $locationRec   = $this->locations->getByKey('RECORD#', $parent);
                        $parent        = $locationRec['PARENTKEY'] ?? 0;
                    }
                }
            }
        }
        $parents = $parentCache;
        return $locationCache;
    }


    /**
     *  If the user has given us parameters like the STARTDATE, ENDDATE, ITEM, WAREHOUSE, or LOCATION,
     *  encode them for a sql query
     *
     * @param string[]      $params           parameters from the user
     * @param string        $whereParams      add this to the sql where clause
     * @param array         $qry              the running query, on entry should have the first fiew entries
     *                                        reserved.  On output more entries may be taken up
     * @param int[]         $parentLocations  the parent locations of the given location (may be empty)
     *
     * @return bool
     */
    private function paramsToSql($params, &$whereParams, &$qry, &$parentLocations)
    {
        $whereParams = '';
        $ok = $this->cacheLocations() && $this->cacheItems() && $this->cacheWarehouses();
        if (!$ok) {
            return false;
        }

        // These are meta-params, not entered by humans:
        $locationField = $params['LOCATION_FIELD'] ?? 'gl.location#';
        $itemRecField  = $params['ITEM_REC_FIELD'] ?? 'gl.itemdimkey';
        $itemIDField   = $params['ITEM_ID_FIELD']  ?? 'de.itemkey';
        $whseIDField   = $params['WHSE_ID_FIELD']  ?? 'de.warehousekey';
        $dateField     = $params['DATE_FIELD']     ?? 'dh.whencreated';
        $daysBefore    = $params['DAYS_BEFORE']    ?? '0';

        // **** decode the params ****

        $locations    = $this->getLocations($params['LOCATION'] ?? '', $parentLocations);
        if ( ! empty($locations) && ($locationField !== '')) {
            // we want transactions in this location, its children, and its parents
            // below we limit the warehouses, so you can fetch only txns that AFFECT your location,
            // even if they were acted on by the parent location (like root using the Arizona Warehouse)
            // but, we want to KNOW whether it was in the location/children or parents, as the GL report would
            // not show the parents but the Item Activity would....
            $whereParams .= ' and ' . $locationField . ' IN (' . implode(',', array_merge($locations, $parentLocations)) . ')';  // record#s so no need to parameterize
        }

        $itemID = trim($params['ITEM'] ?? '');
        if ($itemID != '') {
            $itemRec = $this->items->getByKey('ITEM', $itemID);
            if (($itemRec === null) || (empty($itemRec))) {
                // todo: add error
                throw new Exception("Item '$itemID' is not valid.");
                // return false;
            }
            $itemClause1 = '';
            $itemClause2 = '';
            if ($itemRecField != '') {
                $itemClause1 = " ($itemRecField = " . $itemRec['RECORD#'] . ') ';
            }
            if ($itemIDField != '') {
                $itemClause2 = " ($itemIDField = :" . count($qry) . ') ';
                $qry[] = $itemID;
            }

            if (($itemClause1 != '') && ($itemClause2 != '')) {
                $whereParams .= ' and (' . $itemClause1 . ' or ' . $itemClause2 . ') ';
            } else if (($itemClause1 != '') || ($itemClause2 != '')) {
                $whereParams .= ' and ' . $itemClause1 . $itemClause2; // only one of these is filled in
            }
        }

        if ($whseIDField !== '') {
            $warehouseID = trim($params['WAREHOUSE'] ?? '');
            if ($warehouseID != '') {
                $whereParams .= " and $whseIDField = :" . count($qry);
                $qry[] = $warehouseID;
            } else {
                // if there are locations, but no location field, then restrict via warehouse location
                if (!empty($locations) && ($locationField == '')) {
                    $whs = [];
                    foreach ($this->warehouses as $warehouse) {
                        $location = $warehouse['LOCATIONREFKEY'] ?? 0;
                        if ($location && in_array($location, $locations)) {
                            $whs[] = ':' . count($qry);
                            $qry[] = $warehouse['WAREHOUSE']; // no sql injection
                        }
                    }
                    if (!empty($whs)) {   // hopefully less than 1000 warehouses in this location!
                        $whereParams .= " and $whseIDField IN (" . implode(',', $whs) . ')';
                    }
                }
            }
        }

        $date = trim($params['STARTDATE'] ?? '');
        if ($date != '') {
            $count = count($qry);
            $whereParams .= " and $dateField >= (to_date( :$count, 'YYYY-MM-DD') - $daysBefore) "; // format for html date <input> field
            $qry[] = $date;
        }

        $date = trim($params['ENDDATE'] ?? '');
        if ($date != '') {
            $count = count($qry);
            $whereParams .= " and $dateField <= to_date( :$count, 'YYYY-MM-DD') "; // format for html date <input> field
            $qry[] = $date;
        }

        return true;
    }


    /**
     *  Given a set of ancestor or descendant records, find the next ancestor/descendant for each, if any.
     *      Fill in the running list with what we find
     *      Then recurse up/down the tree....
     *
     * @param string[][]  $docentrycosts          the docentrycost to find the ancestors of
     * @param array       $ancestorsOrDescendants the running ancestor/descendant list
     * @param bool        $getAncestors           true to get ancestors, false to get descendants
     *
     * @return bool                               ok?
     */
    private function findAncestorCommon($docentrycosts, &$ancestorsOrDescendants, $getAncestors)
    {
        $deckeys  = [];
        $lines    = [];
        foreach ($docentrycosts as $docentrycost) {
            $source             = $docentrycost[ $getAncestors ? 'DOCENTRYCOSTKEY' : 'RECORD#' ] ?? 0;
            if ($source) {
                $deckeys[]      = $source;
                $lines[$source] = $docentrycost['FROMLINENO'];
            }
        }

        if (empty($deckeys)) {
            return true;
        }

        $query   = [];
        $query[] = "SELECT dec.record#, dec.docentrycostkey, de.lineno, dh.docparid, dh.docid as document, dec.itemkey as item, 
                            dec.whsekey as warehouse, dec.unitcost, dec.quantity, dec.cost, de.source_doclinekey, de.currency
                    FROM   docentrycost dec, docentrymst de, dochdrmst dh
                    WHERE  dec.CNY# = :1 and de.cny# = dec.cny# and dh.cny# = de.cny#
                      AND  de.record# = dec.docentrykey and dh.record# = de.dochdrkey ";
        $query[] = GetMyCompany();
        $query   = PrepINClauseStmt($query, $deckeys, $getAncestors ? ' and dec.record# ' : ' and dec.docentrycostkey ');
        $result  = QueryResult($query);
        if ($result === false) {
            return false;
        }
        $subDocEntryCosts = [];
        foreach ($result as $row) {
            $recordNumber               = $row[$getAncestors ? 'RECORD#' : 'DOCENTRYCOSTKEY'] ?? 0;
            $row['LINENO']              = ($row['LINENO'] ?? 0) + 1;
            $row['FROMLINENO']          = $lines[$recordNumber] ?? 0;
            $ancestorsOrDescendants[]   = $row;
            $docParID                   = $row['DOCPARID'];

            if ($getAncestors) {
                if ($docParID === ICTransferManager::INDOCTYPE) {
                    // TODO: follow the chain back to the OUT side
                    $recordNumbers = $this->getTransferDocentrycostOutForIn($row); // recordnumbers could be empty
                    foreach ($recordNumbers as $recordNumber => $lineNo) {
                        $row['DOCENTRYCOSTKEY'] = $recordNumber; // the 'source'
                        $row['LINENO']          = $lineNo;
                        $subDocEntryCosts[]     = $row;
                    }
                    continue;
                } else if ($docParID === StkitDocumentManager::BUILDKIT) {
                    // TODO: anything to do here?
                }
            } else {
                if ($docParID === ICTransferManager::OUTDOCTYPE) {
                    // TODO: follow the chain back to the IN side
                } else if ($docParID === StkitDocumentManager::DISKIT) {
                    // TODO: anything to do here?
                }
            }
            if ($row['RECORD#'] !== 0) {
                $subDocEntryCosts[] = $row;
            }
        }

        if ( ! empty($subDocEntryCosts)) {
            return $this->findAncestorCommon($subDocEntryCosts, $ancestorsOrDescendants, $getAncestors); // curses!  He recurses!
        }
        return true;
    }


    /**
     *  Given an IN docentrycost record number for warehouse transfer, find the OUT record.
     *
     * @param  array  $dec      the record of the IN side
     *
     * @return int[]            zero or more record numbers, but could be empty
     */
    private function getTransferDocentrycostOutForIn($dec)
    {
        $recordNumbers = [];
        $source        = $dec['SOURCE_DOCLINEKEY'] ?? 0;
        $lineNo        = '';

            // STEP 1: GET THE RIGHT DOCUMENT AND DOCENTRY
        $found   = false;
        while ( ! $found) { // we expect one or maybe two passes, and that is all
            if ($source) {
                $query = [];
                $query[] = "SELECT de.record#, de.source_doclinekey, de.lineno, dh.docparid
                            FROM   docentrymst de, dochdrmst dh
                            WHERE  de.CNY# = :1 and dh.cny# = de.cny#
                              AND  dh.record# = de.dochdrkey
                              AND  de.record# = :2 ";
                $query[] = GetMyCompany();
                $query[] = $source;
                $result = QueryResult($query);
                if (($result === false) || empty($result)) {
                    break;
                } else {
                    foreach ($result as $row) {
                        // is this the INTERMEDIATE document?
                        $found = ($row['DOCPARID'] === ICTransferManager::OUTDOCTYPE);
                        if ( ! $found) {
                            $source = $row['SOURCE_DOCLINEKEY'] ?? 0;   // hopefully there is just one hop
                            $lineNo = $row['LINENO'];
                        }
                    }
                }
            } else {
                break;
            }
        }

        // STEP 2: GET THE DOCENTRYCOSTS FOR THAT DOCENTRY
        if ($source) {
            $query   = [];
            $query[] = "SELECT dec.record#
                        FROM   docentrycost dec, docentrymst de
                        WHERE  dec.CNY# = :1 and de.cny# = dec.cny#
                          AND  de.record# = dec.docentrykey
                          AND  de.record# = :2 ";
            $query[] = GetMyCompany();
            $query[] = $source;
            $result = QueryResult($query);
            if ($result !== false) {
                // we hope there is only one source layer; that's the way it is supposed to work,
                // but I'm guessing there could be exceptions.
                foreach ($result as $row) {
                    $recordNumbers[$row['RECORD#']] = $lineNo;
                }
            }
        }
        return $recordNumbers;
    }


    /**
     *  Given a set of ancestor records, find the next ancestor for each, if any.
     *      Fill in the running ancestors list with what we find
     *      Then recurse up the tree....
     *
     * @param string[][]  $docentrycosts          the docentrycost to find the ancestors of
     * @param array       $ancestors              the running ancestor list
     *
     * @return bool                               ok?
     */
    private function findAncestors($docentrycosts, &$ancestors)
    {
        return $this->findAncestorCommon($docentrycosts,$ancestors, true);
    }


    /**
     *  Given a set of docentrycost records, find the next descendant for each, if any.
     *      Fill in the running descendants list with what we find
     *      Then recurse down the tree....
     *
     * @param string[][]  $docentrycosts          the docentrycost to find the ancestors of
     * @param array       $descendants            the running descendant list
     *
     * @return bool                               ok?
     */
    private function findDescendants($docentrycosts, &$descendants)
    {
        return $this->findAncestorCommon($docentrycosts,$descendants, false);
    }


    /**
     * Generate CSV from a table.
     *  The table should have NUMERIC INDEXES (0,1,2,..).
     *  Each row of the table should have the same values, i.e. NO MISSING VALUES.
     *
     * Note that in a regular db query the values may be omitted if the value in the table is null.
     *      Beware of this, as then the CSV will be mis-aligned.  For example, use 'nvl(field,'')'
     *
     * @param array     $table      A table of rows where each column has the same values
     *
     * @return string               The CSV blob with its header
     */
    private function tableToCSV($table)
    {
        $blob = '';
        foreach ($table as $index => $row) {
            if ($index === 0) {
                $comma = '';
                foreach ($row as $header => $field) {

                    // can we translate this to i18n??
                    // Place your tokens in the constructor and put them in the sql queries
                    $i18nHeader = 'IA.' . strtoupper($header);
                    $hi18n      = GT($this->translatedText, $i18nHeader);
                    if ($hi18n !== $i18nHeader) {
                        $header = $hi18n;
                    }

                    $blob  .= $comma . $this->escapeForCSV($header);
                    $comma  = ',';
                }
                $blob .= "\n";
            }
            $comma = '';
            foreach ($row as $field) {
                $blob  .= $comma . $this->escapeForCSV($field);
                $comma  = ',';
            }
            $blob .= "\n";
        }
        return $blob;
    }


    /**
     * fputcsv() demands a a file, addslashes() doesn't do what I want.
     *  Excel and Google Docs use "" around strings with commas, and escape " with " before it ("")
     *
     * So this generates CSV that excel likes.....
     *
     * @param bool|string $s        a value you want to put into csv
     *
     * @return string
     */
    private function escapeForCSV($s)
    {
        static $yes = null;
        static $no  = null;

        if ($s === null) {
            $rtn = '';
        } else if (is_bool($s)) {
            if ($yes === null) {
                $yes = GT($this->translatedText, 'IA.YES');
                $no  = GT($this->translatedText, 'IA.NO');
            }
            $rtn = ($s ? $yes : $no);
        } else if (is_numeric($s)) {
            $rtn = "\"$s\""; // This doesn't matter; Excel still treats it as a number even if it is really a string, like a numeric item id.
        } else {
            $rtn = ($s === '') ? '' : str_replace('"', '""', $s);    // escape double quotes
            if ((strpos($rtn, '"') !== false) ||
                (strpos($rtn, "\n") !== false) ||
                (strpos($rtn, ',') !== false)) {
                $rtn = '"' . $rtn . '"';
            }
        }
        return $rtn;
    }


    /**
     *      Given a CSV blob, download it to the customer's machine with the filename (.csv) given.
     *  Note that this should be in response to an AJAX call, not a form refresh.
     *
     * @param string  $fileName
     * @param string  $blob
     *
     */
    private function downloadCSV($fileName, $blob)
    {
        // From reporter.cls:
        // Ticket 41964 : Excel exports working as 'web page' and in 'read only mode'
        if (isl_stristr($_SERVER['HTTP_USER_AGENT'], "msie") ||
            isl_stristr($_SERVER['HTTP_USER_AGENT'], "Trident/7.0; rv:11.0")) {
            $dispHeader = "attachment;";
        } else {
            $dispHeader = "";
        }
        header("Content-Disposition: $dispHeader filename=\"$fileName.csv\"");
        header("Content-type: application/vnd.ms-excel");

        echo $blob;
    }

    /**
     * @param array $params
     *
     * @return array|false
     */
    public function getComponentUsageTable(array $params)
    {
        global $gErr;
        if (!isset($params['ITEM']) || trim($params['ITEM'])=='') {
            $msg = 'Please specify a component item in the item dropdown';
            $gErr->addIAError('INV-1101', __FILE__ . ':' . __LINE__, $msg, []);
            return false;
        }

        $ok = ($this->getComponentUsageData(trim($params['ITEM'])));
        if (!$ok) {
            return false;
        }

        $table = [];
        foreach ($this->wheredUsedItems as $wuItems) {
            $row = [
                'LEVEL'                 => $wuItems['LEVEL'],
                'PARENT ITEM ID'        => $wuItems['PARENTID'],
                'PARENT ITEM TYPE'      => $wuItems['PARENTITEMTYPE'],
            ];
            $key = 'K' . $wuItems['LEVEL'] . ' ~ ' . $wuItems['PARENTID'] . ' ~ ' . $wuItems['PARENTITEMTYPE'];
            $table[$key] = $row;
        }

        ksort($table);
        return array_values($table);
    }

    /**
     * @param string $componentId
     *
     * @return bool
     */
    private function getComponentUsageData(string $componentId)
    {
        $this->wheredUsedItems = new InvCache();
        $qry   = [];
        $qry[] = "SELECT distinct level
                    , iic.itemkey as parentId
                    , case 
                        when parentItem.itemtype = 'K' then 'Kit' 
                        when parentItem.itemtype = 'SK' then 'Stockable Kit'	
                        else parentItem.itemtype 
                      end as parentItemType
                    FROM icitemcomponent iic
                    INNER JOIN icitem parentItem on parentItem.CNY# = iic.CNY# AND parentItem.itemid = iic.itemkey
                    WHERE iic.cny#= :1
                    START WITH iic.cny# = :1
                        AND iic.componentkey = :2
                        AND iic.CNY# = parentItem.CNY#
                    CONNECT BY  iic.componentkey = PRIOR iic.itemkey
                        AND iic.cny# = PRIOR iic.cny#
                        AND iic.cny# = :1
                    ORDER BY level";
        $qry[] = GetMyCompany();
        $qry[] = trim($componentId);
        return $this->wheredUsedItems->QueryResult($qry);
    }

}

