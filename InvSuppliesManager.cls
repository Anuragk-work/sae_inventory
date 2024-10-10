<?php



/**
 * A manager class for Inventory Supplies line items
 */

class InvSuppliesManager extends PODocumentEntryManager
{
    // line status'.  These are directly out of the spec page 28.
    // This will end up in the db field 'SUPPLIESSTATUS'
    // and is referenced in 'SUPPLIESLINESOURCE'.
    // Keep them SHORT because we want to store many in the line source field
    const STATUS_NEEDS_VENDOR = 'NV'; // not sure when this would matter
    const STATUS_NEEDS_DELIVERTO = 'D2'; // not in the spec!
    const STATUS_NEEDS_ITEM = 'NI';
    const STATUS_NEEDS_PRICE = 'NP';
    const STATUS_NEEDS_EMPLOYEE = 'NE';
    const STATUS_NEEDS_WAREHOUSE = 'NW';
    const STATUS_NEEDS_SHIP_VIA = 'NSV';

    const STATUS_NEW_REQUEST = 'NEW';
    const STATUS_NOT_READY = 'NR'; // draft, awaiting approvals
    const STATUS_APPROVED = 'AP';
    const STATUS_CONVERTED = 'CONV';
    const STATUS_IN_TRANSIT = 'IT';
    const STATUS_MULTIPLE = 'MULTI';
    const STATUS_AVAILABLE = 'AVAIL';
    const STATUS_PRINTED = 'PRNTD';
    const STATUS_COMPLETED = 'DONE';
    const STATUS_CANCELED = 'CANCELLED';
    const STATUS_AWAITING_ACK = 'AACK';   // Direct ship generated
    const STATUS_AWAITING_PO = 'PO';

    // these are additional things we do, but are not status' per se
    const STATUSDETAILS_IT = 'IT'; // * waiting on an in-transit warehouse transfer
    const STATUSDETAILS_PO = 'PO'; // * waiting on a Purchase
    const STATUSDETAILS_DIRECTSHIP = 'DS'; // waiting on a direct ship
    const STATUSDETAILS_ACKD = 'ACK';
    const STATUSDETAILS_ISSUED = 'IS';
    const STATUSDETAILS_RETURNED = 'RT';

    const STATUSDETAILS_COMPLETED = 'X'; // This is a PREFIX for the above commands.


    // if we convert from a transaction that has one of these in it, then make the status detail be
    //  STATUSDETAILS_COMPLETED . <the existing command>.  If NOT one of these, do not add a status
    const STATUSDETAILS_CONVERTFROM = [ self::STATUSDETAILS_IT, self::STATUSDETAILS_PO, self::STATUSDETAILS_DIRECTSHIP];

    // can we ISSUE non=inventory?  Yes if it is in any of these status'
    const STATUS_OK_TO_ISSUE_NON_INVENTORY = [self::STATUS_MULTIPLE, self::STATUS_PRINTED, self::STATUS_APPROVED,
                                                self::STATUS_NEW_REQUEST, self::STATUS_AWAITING_PO];

    // can we issue a Warehouse Transfer, PO, or Direct Ship?  Yes if it is in any of these status'
    const STATUS_OK_TO_GET_MORE_INVENTORY = [self::STATUS_MULTIPLE, self::STATUS_PRINTED, self::STATUS_APPROVED,
                                                self::STATUS_NEW_REQUEST, self::STATUS_AWAITING_PO, self::STATUS_IN_TRANSIT,
                                                self::STATUS_AVAILABLE];  // even though you COULD issue it right now, allow POs and such too

    const STATUS_OK_TO_GET_MORE_NON_INVENTORY = [self::STATUS_MULTIPLE, self::STATUS_PRINTED, self::STATUS_APPROVED,
                                                self::STATUS_NEW_REQUEST, self::STATUS_AWAITING_PO];



    const SUPPLIESDETAIL_LEN = 1500;  // SQL field length


    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  STATUS MANAGEMENT
    //
    //  **********************************************************************************
    //  **********************************************************************************



    /**
     *  Given a status as it exists in the DB, return a UI version
     *
     * @param string $status         internal status, like 'IT'.  OK if already in external format
     *
     * @return string                external status, like 'Le Oeuf'
     */
    public function internalToExternalStatus($status)
    {
        static $fieldInfo = null;  // the setup takes time, do it once
        if ($fieldInfo === null) {
            $fieldInfo = [];
            foreach (['SUPPLIESSTATUS', 'LINESOURCE'] as $field) {
                $table    = $this->GetFieldInfo($field);
                $internal = $table['type']['validvalues'] ?? [];
                $external = $table['type']['validlabels'] ?? [];
                foreach ($internal as $index => $internalStatus) {
                    $fieldInfo[$internalStatus] = $external[$index];
                }
            }
            $textMap = getLocalizedText(I18N::tokenArrayToObjectArray(array_values($fieldInfo)), $error);
            foreach ($fieldInfo as $internal => $token) {
                $fieldInfo[$internal] = $textMap[$token] ?? $token; // should be there.....
            }
        }
        return $fieldInfo[$status] ?? $status;
    }


    /**
     *  Is the PO/DS set up in inventory config?
     *
     * @param bool      $directShip         Asking about the Direct Ship PO, otherwise asking about the regular PO
     * @param string    $td                 The TD name to check
     * @param bool      $reportErrors       Should I show error messages?
     *
     * @return bool                         true if the po is valid
     */
    public function validatePO( $directShip, $td, $reportErrors = true )
    {
        $ok = true;
        if (($td == '') || ($td == PODocumentManager::SUPPLIESREQUESTDOCTYPE)) {
            $ok = false;
        }

        if ($ok) {
            $poDocumentParamsManager = Globals::$g->gManagerFactory->getManager('podocumentparams');
            $docpar = $poDocumentParamsManager->GetLatestRaw($td);
            $ok = isset($docpar[0]);
            if ($directShip) {
                // must have line-level ship-to
                $ok = $ok && ($docpar[0]['ALLOWEDITDELIVERTO'] === 'T');
            }
        }

        if ( !$ok && $reportErrors) {
            Globals::$g->gErr->addIAError($directShip ? 'INV-1451' : 'INV-1450', __FILE__ . ':' . __LINE__,
                "Specify an active transaction definition in Inventory Configuration for a Supplies Purchase Order.", []);
        }
        return $ok;
    }


    /**
     * @param string    $status     The status from getLineStatus()
     * @param array     $row        The document row, including the item type and the supplies details
     *
     * @return array                Valid actions from the set:
     *                              ISSUE, PO, DIRECTSHIP, LINK, TRANSFER, REPLENISH
     */
    public function actionsForStatus($status, $row)
    {
        static $checkedTDs = false;
        static $dsIsOK;     // can I use the Direct Ship TD?
        static $poIsOK;     // can I use the PO TD?

        // we get called for every line; no point in checking the TDs for every line....
        if ($checkedTDs === false) {
            $checkedTDs = true;

            GetModulePreferences(Globals::$g->kINVid, $invPrefs);
            $dsTD   = $invPrefs['SUPPLIESINVENTORYDS'] ?? '';
            $poTD   = $invPrefs['SUPPLIESINVENTORYPO'] ?? '';
            $dsIsOK = $this->validatePO(true,  $dsTD, false);  // false = don't report errors
            $poIsOK = $this->validatePO(false, $poTD, false);
        }

        $itemType     = $row['ITEM.ITEMTYPE'] ?? ($row['ITEM']['ITEMTYPE'] ?? '');
        $details      = self::getSuppliesDetails($row);
        $ackNeeded    = false;
        $ackSeen      = false;

        foreach ($details as $detail) {

            switch ($detail['COMMAND']) {

                case self::STATUSDETAILS_DIRECTSHIP:
                case self::STATUSDETAILS_COMPLETED . self::STATUSDETAILS_DIRECTSHIP:    // the direct ship was converted to an invoice
                    $ackNeeded = true;
                    break;

                case self::STATUSDETAILS_ACKD:
                    $ackSeen = true;
                    break;

                default:
                    break;
            }
        }

        $isInventory = in_array($itemType, ['Inventory', 'Stockable Kit']);

        // we can issue if inventory with available in a warehouse; or non-inventory in status 'new request'
        $issueOK     = ($status === self::STATUS_AVAILABLE) ||
                        ( ! $isInventory && in_array($status, self::STATUS_OK_TO_ISSUE_NON_INVENTORY));

        // it is ok to do a PO AND in-transit
        // status is new, multi, in-transit, printed, po/ds.
        $ok2getInventory = in_array($status,$isInventory ? self::STATUS_OK_TO_GET_MORE_INVENTORY : self::STATUS_OK_TO_GET_MORE_NON_INVENTORY);

        $poOK        = $poIsOK && $ok2getInventory;

        // Direct Ship is ok when the TD is ok, and you can issue it or get more
        $dsOK        = $dsIsOK && ($issueOK || $ok2getInventory);

        // You can link to an existing PO even if you have not defined a PO; status becomes PO
        $linkOK      = $ok2getInventory;
        $transferOK  = $isInventory && $ok2getInventory;
        $replenishOK = $isInventory && $ok2getInventory;

        $validActions = [];
        if ($issueOK) {
            $validActions[] = 'ISSUE';
        }
        if ($poOK) {
            $validActions[] = 'PO';
        }
        if ($dsOK) {
            $validActions[] = 'DIRECTSHIP';
        }
        if ($linkOK) {
            $validActions[] = 'LINK';
        }
        if ($transferOK) {
            $validActions[] = 'TRANSFER';
        }
        if ($replenishOK) {
            $validActions[] = 'REPLENISH';
        }
        if ($ackNeeded && !$ackSeen) {
            $validActions[] = 'ACK';
        }

        return $validActions;
    }


    /**
     *  Get and cache onhand values for the document; used as a part of setting the line status.
     *
     * @param array $document The document tree, or, at the least, the entries in ['ENTRIES']
     * @param array $entry    One docentry record
     *
     * @return float                    the QOH, or 0
     */
    private static function getOnHand($document, $entry)
    {
        static $onHand = null;

        // first time, get ALL the on-hand values for the document to save queries.
        if ($onHand === null) {
            $onHand = [];       // so we only do this ONCE
            $items = [];
            $whs = [];
            foreach ($document['ENTRIES'] as $oneEntry) {
                $item = $oneEntry['ITEMID'] ?? '';
                $type = $oneEntry['ITEM.ITEMTYPE'] ?? ($oneEntry['ITEM']['ITEMTYPE'] ?? '');  // non-inventory does not need QOH
                $wh = $oneEntry['WAREHOUSE.LOCATION_NO'] ?? ($oneEntry['WAREHOUSE']['LOCATION_NO'] ?? '');
                if ((($type === 'Inventory') || ($type === 'Stockable Kit')) && ($item !== '') && ($wh !== '')) {
                    $items[] = $item;
                    $whs[] = $wh;     // dups are filtered out by the item manager routine...
                }
            }
            if (!empty($items)) {
                $im = Globals::$g->gManagerFactory->getManager('item');
                $onHand = $im->fetchQuantityTotals($items, $whs);
            }
        }

        $item = $entry['ITEMID'] ?? '';
        $wh = $entry['WAREHOUSE.LOCATION_NO'] ?? ($entry['WAREHOUSE']['LOCATION_NO'] ?? '');
        $keyIndx = $item . "--" . $wh;
        // this is the format fetchQuantityTotals() returns things in
        return $onHand[$keyIndx]['qtyonhand'] ?? 0;
    }


    /**
     *      Given a DococumentEntry record, what should the status be?
     *  It is up to the caller to save it if they wish.
     *
     *      Note: at this time, we don't really need to rely on the SAVED status in the DB, as
     *              we re-calculate the status each time.  The reason for this is that the
     *              txn may have been updated by some other code that doesn't update the
     *              status (like a conversion or approval), and we may need to compute
     *              the ONHAND amount.
     *
     * @param array $document the entire document tree
     * @param array $entry    one DococumentEntry record
     *
     * @return string       one of the STATUS_xxxx constants from the top of this file.
     *
     */
    public static function getLineStatus($document, $entry)
    {
        // given a current running status and a possible NEW status,
        // pick the one that is 'more important',
        $setStatus = function($currentStatus, $proposedStatus) {
            // things that come EARLIER are more important.
            // i.e. if you encounter something at position N,
            // it 'wins' over something with position N+M
            $priority = [
                self::STATUS_COMPLETED,
                self::STATUS_CANCELED,

                self::STATUS_NEEDS_VENDOR,
                self::STATUS_NEEDS_DELIVERTO,
                self::STATUS_NEEDS_ITEM,
                self::STATUS_NEEDS_PRICE,
                self::STATUS_NEEDS_EMPLOYEE,
                self::STATUS_NEEDS_WAREHOUSE,
                self::STATUS_NEEDS_SHIP_VIA,    // all the needs are more important than others....

                self::STATUS_NOT_READY,         // approvals
                self::STATUS_APPROVED ,

                self::STATUS_AVAILABLE,
                self::STATUS_MULTIPLE,          // if it is already MULTIPLE that trumps other things that could be part of MULTIPLE
                self::STATUS_IN_TRANSIT,
                self::STATUS_AWAITING_ACK,
                self::STATUS_AWAITING_PO,
                self::STATUS_PRINTED,
                self::STATUS_CONVERTED,         // why would you convert it?
                self::STATUS_NEW_REQUEST,
            ];
            // one completed, one not?  Both completed?
            $completedC     = (substr($currentStatus,  0, 1) === self::STATUSDETAILS_COMPLETED); // format: Xcommand
            $completedP     = (substr($proposedStatus, 0, 1) === self::STATUSDETAILS_COMPLETED);
            $currentSearch  = $currentStatus;
            $proposedSearch = $proposedStatus;
            if ($completedC && ( ! $completedP)) {
                return $proposedStatus;
            } else if ($completedP && ( ! $completedC)) {
                return $currentStatus;
            } else if ($completedC && $completedP) {
                // both completed, pretend they're not
                $currentSearch  = substr($currentStatus,  1);
                $proposedSearch = substr($proposedStatus, 1);
            }
            $currentPos   = array_search($currentSearch,  $priority);   // search with any X removed
            $newStatusPos = array_search($proposedSearch, $priority);
            if (($currentPos === false) || ($newStatusPos === false)) {
                throw new Exception("[Code bug]Missing priority for '$currentStatus' or '$proposedStatus'");
            }
            return ($currentPos < $newStatusPos) ? $currentStatus : $proposedStatus;
        };

        // where to find the fields on the left, so 'DOCUMENT.STATE' becomes '[DOCUMENT][STATE]'
        // to accomidate the different ways the row can be fetched (part of Get(), or Query())
        $normalize = [
            'CONTACTNAME' => 'DELIVERTO',
            'STATE'       => 'DOCUMENT',
            'SHIPVIAKEY'  => 'DOCUMENT',
            'ITEMTYPE'    => 'ITEM',
            'LOCATION_NO' => 'WAREHOUSE',
        ];

        $mustHaves = [ // in the order they'll be checked for
            'ITEMID'                => self::STATUS_NEEDS_ITEM,
            'TRX_PRICE'             => self::STATUS_NEEDS_PRICE,
            'EMPLOYEEID'            => self::STATUS_NEEDS_EMPLOYEE,
            'VENDORID'              => self::STATUS_NEEDS_VENDOR,
            'DELIVERTO.CONTACTNAME' => self::STATUS_NEEDS_DELIVERTO,
            'DOCUMENT.SHIPVIAKEY'   => self::STATUS_NEEDS_SHIP_VIA,
            'DELIVERVIAKEY'         => self::STATUS_NEEDS_SHIP_VIA
        ];

        $status = $entry['SUPPLIESSTATUS'] ?? '';
        if ($status == '') {
            $status = self::STATUS_NEW_REQUEST;
        }
        $statusIsFirm = false;

        // is it flat or hierarchical?  (depends on whether you do Get() or GetList())
        // normalize them so we don't go crazy
        foreach ($normalize as $field => $level) {
            if (isset($entry[$level][$field])) {
                $entry["$level.$field"] = $entry[$level][$field];
            }
        }

        // what is the document state?
        // it can be in each entry if we fetched it, OR it can be in the document if this is a document.
        $state = $entry['DOCUMENT.STATE'] ?? ($document['STATE'] ?? '');
        switch ($state) {
            case DocumentManager::CLOSED_STATE:     // ready to move on....
            case DocumentManager::PENDING_STATE:
                // not firm
                break;

            case DocumentManager::CONVERTED_STATE:
            case DocumentManager::CONVERTED_BY_LINE_STATE:
                $status = self::STATUS_CONVERTED;
                $statusIsFirm = true; // ??
                break;

            case DocumentManager::DECLINED_STATE:       // not approved
            case DocumentManager::EXCEPTION_STATE:      // 3-way match error
                $status = self::STATUS_CANCELED;       // ??
                $statusIsFirm = true;
                break;

            case DocumentManager::APPROVED_STATE:
                $status = self::STATUS_APPROVED;
                break;

            case DocumentManager::DRAFT_STATE:
            case DocumentManager::SUBMITTED_STATE:
            case DocumentManager::PARTIALLY_APPROVED_STATE:
                $status = self::STATUS_NOT_READY;
                $statusIsFirm = true;
                break;

            default:
                // DocumentManager::ANALYZING_STATE:      // file upload in progress
                break;
        }

        // do we have a status now that is not up for discussion?
        if ($statusIsFirm) {
            return $status;
        }

        if ($entry['ITEMID'] === INVSetupManager::SYS_SUPPLY_ITEM) {
            return self::STATUS_NEEDS_ITEM;     // need this to become a 'real' item
        }

        // are we missing something?
        foreach ($mustHaves as $mustHave => $status2) {
            $has = $entry[$mustHave] ?? false;
            if (($has === false) || ($has == '') || ($has == '0') || ($has === '--')) { // so '0' will fire this; PM's say this is right....
                return $status2;
            }
        }

        // does this inventory item need a warehouse?
        //
        $type = $entry['ITEM.ITEMTYPE'] ?? '';  // non-inventory does not need QOH
        $wh   = $entry['WAREHOUSE.LOCATION_NO'] ?? '';

        if ((($type === 'Inventory') || ($type === 'Stockable Kit')) && ($wh == '')) {
            return self::STATUS_NEEDS_WAREHOUSE;
        }

        // When saving a new document there may be a UIQTY but not yet a QUANTITY
        $maybeDone = false;
        $qty       = $entry['QUANTITY'] ?? '';
        if ($qty == '') {
            $qty = ($entry['UIQTY'] ?? 0) * ($entry['MULTIPLIER'] ?? 1); // txns from the UI sometimes do not have a quantity yet
        }

        // Look at the linkages we have and see if they can set the status....
        $multiple  = 0;
        $details   = self::getSuppliesDetails($entry);
        foreach ($details as $row) {
            $cmd     = $row['COMMAND'];

            switch ($cmd) {

                case self::STATUSDETAILS_RETURNED:
                case self::STATUSDETAILS_ISSUED:
                    return self::STATUS_COMPLETED;

                case self::STATUSDETAILS_COMPLETED . self::STATUSDETAILS_DIRECTSHIP:    // the direct ship was converted to an invoice
                case self::STATUSDETAILS_DIRECTSHIP:
                    $cmd = self::STATUS_AWAITING_ACK;
                    break;

                case self::STATUSDETAILS_ACKD:
                    return self::STATUS_COMPLETED;

                case self::STATUSDETAILS_PO:
                    $cmd = '';
                    // and fall through

                case self::STATUS_IN_TRANSIT:
                case self::STATUS_PRINTED:
                    $multiple++;
                    break;

                default:
                    break;
            }

            if ($multiple > 1) {
                $status = self::STATUS_MULTIPLE;
            }
            if ($cmd != '') {
                $status = $setStatus($status, $cmd);
            }
        }

        $qty = round($qty, 6);

        // are we done?  Did we issue/direct ship the entire order?
        if ($maybeDone && ($qty <= 0)) {
            $status = self::STATUS_COMPLETED;
        }

        if ($cmd === self::STATUS_AWAITING_ACK) {
            return self::STATUS_AWAITING_ACK;
        }

        // regardless of printed/in transit/multiple,
        // is there ONHAND?  That trumps the above.
        if (($qty > 0) && (($type === 'Inventory') || ($type === 'Stockable Kit'))) {
            $onHand = self::getOnHand($document, $entry);
            // $qty is the quantity REMAINING that we need (see above)
            if ($onHand >= $qty) {
                $status = self::STATUS_AVAILABLE;
            }
        }
        return $status;
    }


    /**
     *  This is to fill in the LINESOURCE and LINESOURCEQUANTITY fields
     *
     * @param array  $entry        a DocumentEntry or InvSupplies row
     * @param string $lineSource   the returned line source
     * @param string $lineQuantity the returned line quantity
     */
    public static function getLineSourceAndQuantity($entry, &$lineSource, &$lineQuantity)
    {
        $lineSource = '  ';
        $lineQuantity = '  ';

        // we'll take the TOPMOST, or MOST RECENT, line source
        $details = self::getSuppliesDetails($entry);
        foreach ($details as $row) {
            if (in_array($row['COMMAND'], [ self::STATUSDETAILS_IT,
                                            self::STATUSDETAILS_PO,
                                            self::STATUSDETAILS_DIRECTSHIP,
                                            self::STATUSDETAILS_ACKD,
                                            self::STATUSDETAILS_ISSUED,
                                            self::STATUSDETAILS_RETURNED])) {
                $lineSource = $row['COMMAND'];
                $lineQuantity = $row['QUANTITY'];
                return;
            }
        }
    }


    // **** The supply status details ****
    //
    //  This field of about 150 bytes, SUPPLIESSTATUSDETAIL (on DB: SUPPLIESLINESOURCE)
    //  tracks zero or more entries that keep track of the current outstanding work being done:
    //  - have we created a Warehouse Transfer?
    //  - have we created a PO?
    //  - have we attached to an existing PO?
    //  - have we created a direct-ship PO?
    //
    //  And each entry contains:
    //  - the command (a status)
    //  - a record number, if applicable, of the remote entry (the line in the PO or WT, say)
    //  - a quantity, if applicable (how many we're getting from this.
    //
    //  So, for example, you need 10 items:
    //  - 3 are ONHAND
    //  - you transfer 2 from another warehouse
    //  - you make a PO for the other 5
    //
    //  In that example, you'd have an entry for the transfer and PO, what line on that txn and how many you asked for.
    //  ON THE WT or PO, It would have a status with the requesting transaction's line number and quantity!
    //  This way we have a two-way link.  It isn't enforced by the DB, but should suffice.
    //  When the operation is completed, a STATUSDETAILS_COMPLETED is placed in front of the command, so we have history of what we did
    //  (not sure that part will survive, but it sounds cool)
    //
    //  Entries are saved in LIFO order so the most recent activities are likely to show up (i.e. not exceed the field limit)
    //

    /**
     *  Get the SUPPLIESSTATUSDETAIL field and decode it into an array:
     *  Rows of:
     *      COMMAND:    [X] Command (from the status fields; e.g. STATUS_IN_TRANSIT is 'IT')
     *                      X appears in front if the command was completed successfully, like 'XIT'
     *      RECORDNO:   The record number, if applicable, of the remote transaction,
     *                      For example, the documententry line on a Warehouse Transfer or PO
     *      QUANTITY:   The quantity, if applicable, of the command
     *                      For example, the quantity (in BASE UNITS) on the Warehouse Transfer.
     *
     * @param array $entry One DocumentEntry (or rather InvSupplies) line
     *
     * @return array
     */
    public static function getSuppliesDetails($entry)
    {
        $rtn = [];
        $details = $entry['SUPPLIESSTATUSDETAIL'] ?? '';
        if ($details != '') {
            // INTERNAL FORMAT: each row is separated by commas:
            $detailsArray = explode(',', $details);

            // INTERNAL FORMAT: each field in a row is separated by colons:
            foreach ($detailsArray as $row) {
                $rowDetails = explode(':', $row);
                $rtn[] = ['COMMAND' => $rowDetails[0], 'RECORDNO' => $rowDetails[1], 'QUANTITY' => $rowDetails[2], 'DATE' => $rowDetails[3] ?? ''];
            }
        }
        return $rtn;
    }


    /**
     *      Does this docentry record have a specific Supplies 'command'?
     *
     * @param array  $suppliesDetails The running supplies status details from getSuppliesDetails()
     * @param string $command         The command you're looking for
     * @param int    $recordNo        The recordnumber you're looking for, optional
     *
     * @return integer|bool                 false if not found, or the index into the command array it was found in.
     */
    public static function suppliesDetailsHasCommand($suppliesDetails, $command, $recordNo = -1)
    {
        foreach ($suppliesDetails as $index => $row) {
            if ($command == $row['COMMAND']) {
                if (($recordNo <= 0) || ($row['RECORDNO'] == $recordNo)) {
                    return $index;
                }
            }
        }
        return false;
    }


    /**
     *  Save the passed array into the SUPPLIESSTATUSDETAIL field.  This is the array returned by getSuppliesDetails, above
     *  or generated by sister routines below...
     *
     * @param array $detailsArray Array in the EXACT FORMAT returned by getSuppliesDetails, above
     *
     * @return string
     *
     */
    public static function setSuppliesDetails($detailsArray)
    {
        $details = '';
        foreach ($detailsArray as $row) {
            $command   = $row['COMMAND'] ?? '';
            $recordno  = $row['RECORDNO'] ?? 0;
            $quantity  = $row['QUANTITY'] ?? 0;
            $date      = $row['DATE'] ?? '';
            $rowAsText = "$command:$recordno:$quantity:$date";
            $len       = strlen($rowAsText) + 1; // one for the comma separator

            if (($command != '') && ((strlen($details) + $len) < self::SUPPLIESDETAIL_LEN)) {
                if ($details != '') {
                    $details .= ',';
                }
                $details .= $rowAsText;
            }
        }
        return $details;
    }


    /**
     *  Add one command to the running supplies details.  The details are kept in LIFO order
     *
     * @param array  $suppliesDetails The running supplies status details from getSuppliesDetails()
     * @param string $command         One of the status constants from above
     * @param int    $recordno        Record number, if applicable (optional)
     * @param float  $quantity        Quantity, if applicable (optional)
     * @param string $date            The date for the entry (MM/DD/YYYY)
     *
     * @return array                        The updated Supplies Details
     */
    public static function addCommandToSuppliesDetails( & $suppliesDetails, $command, $recordno, $quantity, $date)
    {
        // add to the front of the array
        array_unshift($suppliesDetails, ['COMMAND' => $command, 'RECORDNO' => $recordno, 'QUANTITY' => $quantity, 'DATE' => $date]);

        return $suppliesDetails;
    }


    /**
     *  Cancel one command in the running supplies details, if it exists
     *
     * @param array  $suppliesDetails The running supplies status details from getSuppliesDetails(), above
     * @param string $command         One of the status constants from above
     * @param int    $recordno        Record number, if applicable (optional)
     *
     * @return array                        The updated Supplies Details
     */
    public static function cancelCommandInSuppliesDetails($suppliesDetails, $command, $recordno = 0)
    {
        foreach ($suppliesDetails as $index => $row) {
            if (($command === $row['COMMAND']) && ($recordno === $row['RECORDNO'])) {
                $row['COMMAND'] = self::STATUSDETAILS_COMPLETED . $command;

                // if not already the last command, MAKE it the last command
                // (so if it needs to fall off the end it can)
                $lastIndex = count($suppliesDetails) - 1;
                if ($index < $lastIndex) {
                    unset($suppliesDetails[$index]);
                    array_push($suppliesDetails, $row);
                }
                break;
            }
        }
        return $suppliesDetails;
    }


    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  CRUD
    //
    //  **********************************************************************************
    //  **********************************************************************************

    /**
     *  standard get() but with a twist:
     *      Passing 0 gets all the supplies requisition lines
     *      Passing n > 0 gets one specific docentry record
     *      Passing a string ID gets THAT document's records
     *
     * @param string $ID
     * @param null|array $fields
     *
     * @return array
     */
    function Get($ID, $fields=null)
    {
        $obj = [];
        if (($ID == 0) || ( ! is_numeric($ID))) {
            $obj['LINES'] = $this->getListOfSupplyItems([], $ID);
            return $obj;
        }

        // get a specific DocumentEntry record number other than zero
        // here we get ALL fields not just those used here (for printing and such)
        // (this is for the API)
        $obj = parent::get($ID, $fields);
        $list = [ $obj ];
        $this->processRecordsForSupplies($list);
        return $list[0];
    }




    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  Get List / Get the standard list of supply items for the UI
    //
    //  **********************************************************************************
    //  **********************************************************************************

    /**
     *      Get the list to send to the form, or a list of specific records for, say, printing.
     *
     * @param int[]     $recordNumbers      Optional.  If specified, get these specific records.
     *                                      Otherwise, get ALL records for supplies
     * @param string    $docId              Optional.  If specified, the document ID of the transaction to read from.
     *
     * @return array[]|false
     */
    public function getListOfSupplyItems( $recordNumbers = [], $docId = 0 )
    {
        $selectList = [
            'WHENCREATED', 'DOCID', 'LINE_NO', 'ITEMID', 'ITEMNAME', 'UNIT', 'UIQTY', 'LINESOURCE', 'LINESOURCEQUANTITY',
            'WAREHOUSE.LOCATION_NO', 'WAREHOUSE.NAME', 'TRX_PRICE' /* shouldn't it be COST??? */, 'EMPLOYEEID', 'EMPLOYEENAME',
            'SUPPLIESSTATUS', 'SUPPLIESSTATUSDETAIL', 'DOCUMENT.SHIPVIAKEY', 'DELIVERVIAKEY',
            'QUANTITY', 'ITEMDESC', 'MEMO', 'DELIVERTO.CONTACTNAME','DELIVERTO.PRINTAS','DELIVERTO.MAILADDRESS.ADDRESS1','DELIVERTO.MAILADDRESS.ADDRESS2',
            'DELIVERTO.MAILADDRESS.CITY', 'DELIVERTO.MAILADDRESS.STATE', 'DELIVERTO.MAILADDRESS.ZIP', 'DELIVERTO.MAILADDRESS.COUNTRY',
            'DELIVERTO.MAILADDRESS.COUNTRYCODE', 'LOCATIONID', 'DEPARTMENTID',
            'ITEM.ITEMTYPE', 'RECORDNO', 'DOCUMENT.STATE', 'MULTIPLIER', 'VENDORID','CREATEDBY','REQUESTER'
        ];

        $recordNumbers = $this->sanitizeRecordNumbers($recordNumbers);

        if (empty($recordNumbers)) {
            if ($docId != 0) {
                $filters = [[['DOCID',    '=', $docId]]];
            } else {
                $filters = [[['DOCPARID', '=', PODocumentManager::SUPPLIESREQUESTDOCTYPE]]];
            }
        } else {
            $filters = [[['RECORDNO', 'in', $recordNumbers ]]];
        }

        $list = $this->GetList([  // we are a document entry derivitive
            'selects'       => $selectList,
            'filters'       => $filters,
            'orders'        => [['WHENCREATED', 'DESC'], ['DOCID','ASC']],
            'usemst'        => true
        ]);

        $this->processRecordsForSupplies($list);
        return $list;
    }

    /**
     * @param $list
     * @return void
     */
    private function processRecordsForSupplies(&$list)
    {
        if ($list !== false) {
            $document = ['ENTRIES' => $list];  // so we can get on-hand and such
            foreach ($list as $index => $row) {
                $status = self::getLineStatus($document, $row);;
                self::getLineSourceAndQuantity($row, $lineSource, $lineQuantity);
                $list[$index]['WAREHOUSE'] = "  ";
                if (isset($row['WAREHOUSE.LOCATION_NO']) && ($row['WAREHOUSE.LOCATION_NO'] != '')) {
                    $list[$index]['WAREHOUSE'] = $row['WAREHOUSE.LOCATION_NO'] . '--' . $row['WAREHOUSE.NAME'];
                }
                $list[$index]['ITEM'] = $row['ITEMID'] . '--' . $row['ITEMNAME'];
                $list[$index]['EMPLOYEE'] = " ";
                if (isset($row['EMPLOYEEID']) && ($row['EMPLOYEEID'] != '')) {
                    $list[$index]['EMPLOYEE'] = $row['EMPLOYEEID'] . '--' . $row['EMPLOYEENAME'];
                }
                $list[$index]['VALID_ACTIONS']  = $this->actionsForStatus($status, $row);
                $list[$index]['SUPPLIESSTATUS'] = $this->internalToExternalStatus($status);
                $list[$index]['LINESOURCE'] = $this->internalToExternalStatus($lineSource);
                $list[$index]['LINESOURCEQUANTITY'] = $lineQuantity;
                $list[$index]['LINE_NO'] = ($row['LINE_NO'] ?? 0) + 1;
                $list[$index]['DELIVERTO'] = $row['DELIVERTO.CONTACTNAME'];
            }
        }
    }


    /**
     *      Prior to calling GetList(), we look for fields we support but are not in the DB directly.
     *  Things like 'available', which is an aggregate of the availability of items.
     *
     *  We save this in an array for later processing after the GetList.
     *  We update the parameters so they no longer include the item (which would fail in a DB request).
     *  We may add something like a record number in order to be able to satisfy the request later.
     *
     * @param array $params The client's list of what to get from the query
     *
     */
    private function removeLocalSelectsNotInTheDB(&$params)
    {
        // Fields we remove from the query and get manually later
        $fieldsToRemove = [
            'LINESOURCE', 'LINESOURCEQUANTITY'
        ];

        // Are they in the select statements?
        foreach ($params['selects'] as $index => $select) {
            if (in_array($select, $fieldsToRemove)) {
                unset($params['selects'][$index]);
            }
        }

        $params['selects'] = array_values($params['selects']);  // renumber the entries
    }


    /**
     * Override the Entity Manager GetList() code.
     *
     *   - if an error is generated, throw it as an exception.  The caller only responds to exceptions, not errors.
     *
     * @param array $params    a structure used to build the custom query
     * @param bool  $_crosscny if true do not add the var.cny# = ... code
     * @param bool  $nocount   don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        $this->removeLocalSelectsNotInTheDB($params);
        $rtn = parent::GetList($params, $_crosscny, $nocount);   // DO THE QUERY (cross your fingers!)
        return $rtn;
    }


    /**
     *      When you call Get(), it returns rows slightly differently than GetList() does.
     *  For example, 'flat' things like ITEM.NAME become an array [ITEM][NAME].
     *
     * @param array $params
     * @param false $_crosscny
     * @param bool  $nocount
     *
     * @return array|bool               false, or the array of rows
     */
    public function GetListInTheStyleOfGet($params = [], $_crosscny = false, $nocount = true)
    {
        $list = $this->GetList($params, $_crosscny, $nocount);
        if ($list === false) {
            return false;
        }

        $returnArray = [];
        foreach ($list as $row) {
            $returnArray[] = $this->FlatToStructured($row);
        }
        return $returnArray;
    }


    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  Ajax Call receivers for taking actions
    //
    //  **********************************************************************************
    //  **********************************************************************************

    /**
     *  Given an array of record numbers, or a string with record numbers in it ("1,2,"),
     *      Turn them into a real array of integers
     *
     * @param   int[]|string    $recordNumbers      an array of numbers, or a string with numbers
     *
     * @return int[]                                any record numbers found (might be empty)
     */
    public function sanitizeRecordNumbers($recordNumbers)
    {
        $rtn = [];
        if ( ! is_array($recordNumbers)) {
            $recordNumbers = explode( ',', $recordNumbers);
        }

        foreach ($recordNumbers as $record) {
            if (is_numeric($record) && ($record > 0)) {
                $rtn[] = $record;
            }
        }
        return $rtn;
    }


    /**
     *  Take action from the UI
     *
     * @param string    $action         action.  like 'ACK' or 'REFRESH'
     * @param array     $rows           array of rows the action pertains to
     * @param bool      $refresh        [out] should the UI refresh itself?
     *
     * @return bool
     */
    public function takeAction($action, $rows, & $refresh)
    {
        $refresh = false;
        if ( ! ItemManager::isSuppliesInventoryEnabled()) {
            return true;
        }

        $ok = true;
        if ($action === 'ACK') {
            $documentTree                        = [];
            $documentTree['SUPPLIES_REQUEST']    = self::STATUS_COMPLETED;  // so other code knows
            $documentTree['SUPPLIES_ACTION']     = "ACK";
            $documentTree['IGNORE_STATUS_CHECK'] = true;
            $records            = $this->sanitizeRecordNumbers($rows);
            $ok = $ok && $this->gatherLineItemsForConversion($documentTree, $records);  // well, not CONVERSION per se....
            if ($ok) {
                $today          = GetCurrentDate();
                $cny            = GetMyCompany();
                $updateArray    = [];
                foreach ($documentTree['ENTRIES'] as $row) {
                    $status       = self::getLineStatus($documentTree, $row);
                    $validActions = $this->actionsForStatus($status, $row);
                    if (in_array(self::STATUSDETAILS_ACKD, $validActions)) {
                        // they ack'd and it is needed, so save it:
                        $foundDS = 0;
                        $suppliesDetails = self::getSuppliesDetails($row);
                        foreach ($suppliesDetails as $detail) {
                            if ($detail['COMMAND'] == self::STATUSDETAILS_DIRECTSHIP) {
                                $foundDS = $detail['RECORDNO'];
                            }
                        }
                        self::addCommandToSuppliesDetails($suppliesDetails, self::STATUSDETAILS_ACKD, $foundDS, $row['QUANTITY'], $today);
                        $updateArray[] = [$cny, $row['RECORDNO'], self::setSuppliesDetails($suppliesDetails) ];    // ORDER IS IMPORTANT
                    }
                }

                $ok = $ok && $this->bulkUpdate('docentrymst',
                                    "supplieslinesource = :3(i) ",   // internal name of SUPPLIESSTATUSDETAIL
                                    "cny# = :1(i) AND record# = :2(i) ",
                                        ['integer', 'integer', 'char'],
                                        $updateArray); // values must be in the 1, 2, 3 order!
                $refresh = true;
            }
            return $ok;
        }

        throw new Exception("[Code bug] '$action' not implemented yet");
        //return true;
    }


    /**
     * @param array $rows
     * @param array $whatHappened
     *
     * @return bool
     */
    public function bulkConvert($rows, &$whatHappened)
    {
        throw new Exception("[Code bug] bulk convert not implemented $rows, $whatHappened");
        // return true;
    }


    //  **********************************************************************************
    //  **********************************************************************************
    //
    //  HELPERS FOR OUR SIMULATED CONVERSTIONS AND FOR MAINTAINING LINKS
    //
    //  **********************************************************************************
    //  **********************************************************************************


    /**
     *      We use the conversion code to 'convert' a supplies request to an issue.
     *  In reality, the supplies request is based on a Purchase Requisition form,
     *  and the Issue is based on an Inventory Adjutment.  AND, we want to take several
     *  line items from various requisition documents and put them on ONE issue.
     *
     *      So, this is not normal behavior and won't work as smoothly as a real conversion
     *  (like, when you delete the issue it can't put back the various supplies), but this
     *  is what the design says is required....
     *
     * @param array $targetTransaction     the transaction we are converting from/to
     * @param int[] $lineItemRecordNumbers the record numbers of the lines we want to convert
     *
     * @return bool
     */
    public function gatherLineItemsForConversion(&$targetTransaction, $lineItemRecordNumbers)
    {
        // *************************
        // **** HELPER ROUTINES ****
        // *************************

        // Fetch all the lines needed, from one or more source transactions
        /** @var callable $fetchEntriesFromTransactions */
        $fetchEntriesFromTransactions = function ($linesToFetch, $action) use($targetTransaction) {
            $list = [];
            if (!empty($linesToFetch)) {
                $selects = $this->GetGetFields();       // list to get
                $selects[] = 'DOCUMENT.STATE';          // document's state so we can compute the status
                $selects[] = 'LOCATIONKEY';
                $selects[] = 'DOCUMENT.SHIPVIAKEY';
                $selects[] = 'DELIVERVIAKEY';
                if ($action === self::STATUSDETAILS_PO) { // don't send it to their home
                    unset($selects['DELIVERTOADDRESS'], $selects['DELIVERTOKEY']);  // remove the ship via info
                }
                $list = $this->GetListInTheStyleOfGet([
                    'selects'       => $selects,
                    'filters'       => [[['RECORDNO', 'in', $linesToFetch]]],
                    'usemst'        => true
                ]);
                if ($list === false) {
                    return false;
                }

                $textMap  = getLocalizedText(I18N::tokenArrayToObjectArray(['IA.LINE_NUMBER']), $error);
                $lineNo   = $textMap['IA.LINE_NUMBER'];

                $document = ['ENTRIES' => $list];
                foreach ($list as $index => $row) {
                    $status                         = self::getLineStatus($document, $row);
                    $list[$index]['SUPPLIESSTATUS'] = $status;
                    $list[$index]['VALID_ACTIONS']  = $this->actionsForStatus($status, $row);
                    $list[$index]['LOCATION']       = $row['LOCATIONID'] . '--' . $row['LOCATIONNAME'];
                    $list[$index]['DEPARTMENT']     = $row['DEPARTMENTID'] . '--' . $row['DEPARTMENTNAME'];
                    $list[$index]['COST']           = $row['PRICE'];    // to start with; the PRICE on a purchase is the estimated COST
                    $list[$index]['MEMO']           = $row['DOCHDRID'] . " $lineNo " . (($row['LINE_NO'] ?? 0) + 1);

                    if ($targetTransaction['SUPPLIES_CANT_EXCEED_SOURCE_QTY'] ?? false) {
                        $list[$index]['MAX_QUANTITY'] = $row['QUANTITY'];
                    }
                }
            }
            return $list;
        };


        // Check to make sure the status is correct.
        /** @var callable $filterRows */
        $validateRows = function ($entries, $command) {
            foreach ($entries as $row) {
                $type     = $row['ITEM.ITEMTYPE'] ?? ($row['ITEM']['ITEMTYPE'] ?? '');
                $statusOk = in_array($command, $row['VALID_ACTIONS']);

                if (!$statusOk) {
                    $err = 'PO-0181';   // generic 'wrong status for action' error
                    if ($command === 'ISSUE') {
                        $err = 'PO-0177';  // issue an item
                        // if non-inventory in the right status, pretend its available
                        if (($type !== 'Inventory') && ($type !== 'Stockable Kit')) {
                            $err = 'PO-0180';  // issue a non-inventory item
                        }
                    }

                    $itemID = $row['ITEMID'];
                    $lineno = ($row['LINE_NO'] ?? 0) + 1;
                    Globals::$g->gErr->addIAError($err, __FILE__ . ':' . __LINE__,
                        'Not the right status', [], "Lines must be in 'Available' state to issue $itemID / $lineno",
                        ['ITEMID' => $itemID, 'LINENO' => $lineno]);
                    return false;
                }
            }
            return true;
        };


        // *************************
        // ******  MAIN CODE  ******
        // *************************
        $ok = true;

        if (ItemManager::isSuppliesInventoryEnabled() && (!empty($lineItemRecordNumbers))) {
            // Construct the list of records we want to fetch, and remove any records
            // from this transaction we DON'T want to convert.
            //
            //      Use case:
            //          You create a supplies request for a laptop and chair.
            //          The workbench user says to go issue the chair, but NOT the laptop.
            //          Here we remove the laptop line.
            //
            //      Bulk use case:
            //          You create a supplies request for a laptop and chair.
            //          Other users also ask for stuff, including chairs
            //          The workbench user highlights all the CHAIR lines and asks to bulk-issue them.
            //          Here we remove the laptop line, AND we read all the other chair lines and add them
            //              into 'target transaction' rows
            //

            $linesToFetch = $this->sanitizeRecordNumbers($lineItemRecordNumbers);
            $entries      = [];
            if (!empty($linesToFetch)) {

                $action  = $targetTransaction['SUPPLIES_ACTION'];

                // Get the other records for a bulk operation; don't get line-level ship to for a PO
                $entries = $fetchEntriesFromTransactions($linesToFetch, $action);
                if ($entries === false) {
                    return false;
                }

                // make sure the row STATE is ok
                if ($validateRows($entries, $action) === false) {
                    return false;
                }

                $targetTransaction['ENTRIES'] = $entries;
            }
            if (empty($entries)) {
                Globals::$g->gErr->addIAError('PO-0178', __FILE__ . ':' . __LINE__,
                    'Nothing to issue', [], "There are no inventory items to issue");
                return false;
            }
        }
        return $ok;
    }


    /**
     *  In the editors, processCopyConvert() gets called when someone wants to do a conversion or copy.
     *  This code is to make it easy for editors, or someday, the REST API, can invoke a conversion.
     *
     *
     * @param string    $copy               'copy' or 'convert'
     * @param array     $documentTree       Document tree, from an EntityManager::Get()
     * @param string    $action             The supplies command, like 'ISSUE', 'PO', or 'DIRECTSHIP'
     * @param string    $recordsAsString    record numbers separated by commas ( "123,444,356" )
     *
     * @return bool
     */
    public function processCopyConvert($copy, &$documentTree, $action, $recordsAsString)
    {
        $ok = true;
        if (ItemManager::isSuppliesInventoryEnabled() && ($copy === 'Update')) {

            // If the transaction being converted is supplies inventory's 'supply request', process it specially
            if ($documentTree['DOCPARID'] === PODocumentManager::SUPPLIESREQUESTDOCTYPE) {

                switch ($action) {
                    case 'ISSUE':
                        $command = self::STATUSDETAILS_ISSUED;
                        $documentTree['SUPPLIES_CANT_EXCEED_SOURCE_QTY'] = true; // can't issue more than requested
                        break;

                    case 'PO':
                        $command = self::STATUSDETAILS_PO;
                        break;

                    case 'DIRECTSHIP':
                        $command = self::STATUSDETAILS_DIRECTSHIP;
                        $documentTree['SUPPLIES_CANT_EXCEED_SOURCE_QTY'] = true; // can't direct-ship more than requested
                        break;

                    default:
                        logFL("[Code Bug] Unknown or not-yet-implemented conversion action: $action");
                        return true; // ignore
                }

                $documentTree['SUPPLIES_REQUEST']    = $command;  // so other code knows
                $documentTree['SUPPLIES_ACTION']     = $action;
                $documentTree['IGNORE_STATUS_CHECK'] = true;
                $records         = explode(',', $recordsAsString);
                $ok              = $this->gatherLineItemsForConversion($documentTree, $records);
            }
        }
        return $ok;
    }


    /**
     *  Processing for a supplies issue/PO/whatnot, particularly when 'converting' from a supply request.
     *
     *  This is called in Add(), prior to EntityManager::Add(), so the entries are saved.
     *
     *
     * @param array $documentTree       The document tree
     *
     * @return bool
     *
     */
    public function createLinksInDocumentFromConvertSource( & $documentTree)
    {
        // **** HELPERS ****

        /** @var callable  $isANormalConvert */
        $isANormalConvert = function($documentTree) {
            $shouldBeHere = true;
            $sourceDocs   = [];
            foreach ($documentTree['ENTRIES'] as $docEntry) {
                $deDocpar      = $docEntry['DOCPARID'] ?? '';  // not yet reset???
                $source        = $docEntry['SOURCE_DOCID'] ?? '';
                $apiConversion = (($deDocpar == '') && ($source != '') &&
                    (($documentTree['FROMAPI_2.1'] ?? false) === true) &&
                    (($docEntry['SOURCE_DOCKEY'] ?? 0) > 0));
                if ( ! $apiConversion && (($deDocpar == '') || ($deDocpar === $documentTree['DOCPARID']))) {
                    $shouldBeHere = false;  // oops, it has a source, but it isn't a convert....
                    break;
                }
                if ($source != '') {
                    $sourceDocs[$source] = $docEntry['DOCHDRNO'] ?? ($docEntry['SOURCE_DOCKEY'] ?? 0);
                }
            }

            // no source? no conversion.  Too many sources?  Not the kind of conversion I can deal with yet
            // TODO: what happens when you multi-convert?
            $shouldBeHere = $shouldBeHere && (count($sourceDocs) === 1);

            return $shouldBeHere;
        };

        /** @var callable $markSuppliesRecords */
        $markSuppliesRecords = function( & $documentTree) {
            // is any entry a supplies record?
            $isSupplyRelatedTransaction = false;
            if (isset($documentTree['ENTRIES'])) {
                foreach ($documentTree['ENTRIES'] as $index => $entry) {
                    $documentTree['ENTRIES'][$index]['SUPPLIESITEM'] = false;    // remember this for ease of testing later
                    if (isset($entry['ITEMID']) && ($entry['ITEMID'] != '') && // not an empty line, right?
                        PODocumentEntryManager::isSupplyItem($entry)) {
                        $documentTree['ENTRIES'][$index]['SUPPLIESITEM'] = true;
                        $isSupplyRelatedTransaction = true;
                    }
                }
            }
            return $isSupplyRelatedTransaction;
        };



        // **** MAIN CODE ****
        $documentTree['SUPPLIES_CONVERSION'] = false;           // until we know otherwise
        if ( ! ItemManager::isSuppliesInventoryEnabled()) {
            return true;
        }

        // is any part of this transaction related to a supplies request?
        if ( ! $markSuppliesRecords($documentTree)) {
            return true; // not one of ours!
        }

        // is it a draft?
        $draft = $documentTree['STATE'] === DocumentManager::DRAFT_STATE;

        $isConversion = ( ! $draft) &&
            isset($documentTree['ENTRIES']) &&
            (isset($documentTree['HISTORY'][0]['DOCUMENTID']) && ($documentTree['HISTORY'][0]['DOCUMENTID'] != '')) &&
            (isset($documentTree['CREATEDFROM']) && ($documentTree['CREATEDFROM'] != ''));

        $documentTree['SUPPLIES_CONVERSION'] = $isConversion;
        $isRegularConversion = $isConversion && $isANormalConvert($documentTree);
        $newDocPar           = $documentTree['DOCPARID'];
        $command             = ($documentTree['SUPPLIES_REQUEST'] ?? '');

        if ($isRegularConversion && ($command === '')) {
            $removeConversionFields  = false;   // no, because it is a 'real' conversion

            // For Supply ---> Issue from a CONVERT
            // For Issue ---> Return from a CONVERT (we don't offer this from the workbench)
            // For Issue ---> PO
            // For PO    ---> RECEIVER/INVOICE
            $isConversionFromRequest = true;

            GetModulePreferences(Globals::$g->kINVid, $invPrefs);
            $dsTD   = $invPrefs['SUPPLIESINVENTORYDS'] ?? '';
            $poTD   = $invPrefs['SUPPLIESINVENTORYPO'] ?? '';

            switch ($newDocPar) {
                case PODocumentManager::SUPPLIESISSUEDOCTYPE:
                    $command = self::STATUSDETAILS_ISSUED;
                    break;

                case PODocumentManager::SUPPLIESRETURNDOCTYPE:
                    $command = self::STATUSDETAILS_RETURNED;
                    break;

                case $dsTD:
                    $poIsOK = $this->validatePO(true,  $dsTD, false);  // false = don't report errors
                    $command = $poIsOK ? self::STATUSDETAILS_DIRECTSHIP : self::STATUSDETAILS_COMPLETED;    // todo: not sure this is right
                    break;

                case $poTD:
                    $poIsOK = $this->validatePO(true,  $poTD, false);  // false = don't report errors
                    $command = $poIsOK ? self::STATUSDETAILS_PO : self::STATUSDETAILS_COMPLETED;
                    break;

                // TODO: put others here, like generating a WT

                default:
                    // maybe it is a conversion from, say, a PO --> RECEIVER/INVOICE??
                    // so PO ----> RECEIVER, the PO command gets a STATUSDETAILS_COMPLETED in front of it ('completed')
                    $command = self::STATUSDETAILS_COMPLETED; // Special case: just slap an X in front of the source's commands....
                    break;
            }

        } else {
            // For Requisition ---> Issue from the workbench (or Requisition --> PO, etc):
            //      We used a BUNCH of the conversion code to get here (so it copies data and sets things up right),
            //      but we aren't ACTUALLY CONVERTING using the standard conversion process, and so we also don't want to
            //      leave behind the fields that tell the rest of the code that this WAS a conversion.
            $isConversionFromRequest = $isConversion && ($command !== '');
            $removeConversionFields  = $isConversionFromRequest; // yes, if we do our phoney workbench conversion
        }

        $ok = true;
        if ($isConversionFromRequest) {
            $documentTree['SUPPLIES_COMMAND'] = $command;
            foreach ($documentTree['ENTRIES'] as $index => $entry) {
                if ($entry['SUPPLIESITEM']) {   // this row is a supplies item
                    // if you, say, convert a PO to a RECEIVER, the existing SUPPLIESSTATUSDETAIL is the PO's,
                    //    not the RECEIVERs.
                    $documentTree['ENTRIES'][$index]['SOURCE_SUPPLIESSTATUSDETAIL'] = $entry['SUPPLIESSTATUSDETAIL'] ?? '';
                    $documentTree['ENTRIES'][$index]['SUPPLIESSTATUSDETAIL']        = ''; // so we don't inherit the source's links directly

                    // some fields are PO-only; remove those from INV txns so the fields aren't attempted to be written
                    // (or not written, because 'true' does not become 'T')
                    if (($command === self::STATUSDETAILS_ISSUED) || ($command === self::STATUSDETAILS_RETURNED)) {
                        unset($documentTree['ENTRIES'][$index]['INCLUDETAXINASSETCOST'],
                              $documentTree['ENTRIES'][$index]['NAMEOFACQUIREDASSET']);
                    }
                }
            }
            $ok = $this->setLinksInRequest( $documentTree, $command );
        }

        // was this a 'pretend' conversion (i.e. from the workbench, not a full-on conversion)?
        if ($removeConversionFields) {
            $this->clearAnyTracesOfConversion($documentTree);
        }
        return $ok;
    }


    /**
     *  When creating an 'Issue' or other sorta-conversion-like transactions, we go through SOME of the convert code
     *  because it helps us make a copy, but we don't want all the downstream tracking and linking because we're converting
     *  parts of many documents into one.
     *
     *  Here we clean out the various fields that folks use to see if this is a conversion.
     *
     * @param array     $document       document tree
     *
     */
    public function clearAnyTracesOfConversion( & $document)
    {
        unset($document['CREATEDFROM'], $document['SUPPLIES_REQUEST'], $document['HISTORY']);
        if (isset($document['ENTRIES'])) {
            foreach ($document['ENTRIES'] as $index => $row) {
                unset(  $document['ENTRIES'][$index]['SOURCE_DOCKEY'],
                        $document['ENTRIES'][$index]['SOURCE_DOCLINEKEY'],
                        $document['ENTRIES'][$index]['SOURCE_DOCID'],
                        $document['ENTRIES'][$index]['QTY_REMAINING'],
                        $document['ENTRIES'][$index]['RELATEDDOCKEY'],
                        $document['ENTRIES'][$index]['RELATEDDOCLINEKEY'],
                        $document['ENTRIES'][$index]['ADDEDBYCHANGE'],
                        $document['ENTRIES'][$index]['HASCHANGE'],
                        $document['ENTRIES'][$index]['REVERSECONVERSION']);
            }
        }
    }


    /**
     *      Given a Supplies Issue/Return document tree, set links in the docentry lines
     *
     * @param array     $document               The document tree from the UI or API
     * @param string    $command                The command to add to the supplies details status
     *
     * @return bool
     */
    private function setLinksInRequest(&$document, $command)
    {
        // ****** HELPERS *******

        /** @var callable $maybeTakePriorLinks */
        $maybeTakePriorLinks = function( & $suppliesDetails, $command, $row) {

            // is this a basic command (PO, IS, WT, ...)?  Then don't drag other stuff along.
            if (in_array($command, self::STATUSDETAILS_CONVERTFROM) ||
                ($command === self::STATUSDETAILS_ISSUED)) {
                return;
            }

            // use case:
            // ISSUE --> RETURN   Look for ISSUED in the links, save RETURNED in the current document
            // PO --> RECEIVER (or other <known> conversion) Look for PO and make our new command
            //      be the completed version of the original
            // others are ignored (i.e. RECEIVER --> INVOICE we don't keep the links)
            $sourceDetailsRaw = $row['SOURCE_SUPPLIESSTATUSDETAIL'];
            $sourceDetails    = self::getSuppliesDetails(['SUPPLIESSTATUSDETAIL' => $sourceDetailsRaw]);
            foreach ($sourceDetails as $link) {
                if (($link['COMMAND'] === self::STATUSDETAILS_ISSUED) && ($command === self::STATUSDETAILS_RETURNED)) {
                    $link['COMMAND'] = $command; // change it to a return
                    array_unshift($suppliesDetails,  $link); // as is, the record numbers are (hopefully) valid
                } else if ($command === self::STATUSDETAILS_COMPLETED) {
                    $indexFoundAt = array_search($link['COMMAND'], self::STATUSDETAILS_CONVERTFROM);
                    if ($indexFoundAt !== false) {
                        $link['COMMAND'] = self::STATUSDETAILS_COMPLETED . self::STATUSDETAILS_CONVERTFROM[$indexFoundAt];
                        array_unshift($suppliesDetails,  $link);
                    }
                }
            }
        };


        // **** MAIN CODE ******
        $ok = true;
        if (isset($document['SUPPLIES_CONVERSION']) && ($document['SUPPLIES_CONVERSION'] === true)) {
            $today = GetCurrentDate();
            foreach ($document['ENTRIES'] as $index => $row) {
                // is this a real line or a dummy line?
                if ($row['SUPPLIESITEM'] ?? false) {
                    $suppliesDetails = self::getSuppliesDetails($row);

                    // If the source transaction already has links, maybe we need to preserve some.
                    $maybeTakePriorLinks($suppliesDetails, $command, $row);

                    $sourceRecord    = $row['SOURCE_DOCLINEKEY'] ?? 0;
                    $targetQuantity  = $row['QUANTITY'] ?? '';
                    // txns from the UI sometimes do not have a quantity yet
                    if ($targetQuantity == '') {
                        $targetQuantity = ibcmul(($row['UIQTY'] ?? 0), ($row['MULTIPLIER'] ?? 1), 10, true);
                    }
                    // if someone tries to issue or direct-ship more than the original request, bitch at 'em.
                    // more PO, link, or transfer is just fine.
                    if (isset($row['MAX_QUANTITY']) && ($targetQuantity > $row['MAX_QUANTITY'])) {
                        $lineNo = $index + 1;
                        $itemid = $row['ITEMID'];
                        Globals::$g->gErr->addIAError('INV-1451', __FILE__ . ':' . __LINE__,
                            "On line $lineNo for item $itemid the quantity ($targetQuantity) cannot exceed the quantity on the original Supply Requisition.",
                                    ['ITEMID' => $itemid, 'LINENO' => $lineNo, 'QTY' => $targetQuantity, 'MAX_QTY' => $row['MAX_QUANTITY']]);
                        $ok = false;
                        break;
                    }

                    self::addCommandToSuppliesDetails( $suppliesDetails, $command, $sourceRecord, $targetQuantity, $today);
                    $document['ENTRIES'][$index]['SUPPLIESSTATUSDETAIL'] = self::setSuppliesDetails( $suppliesDetails);
                    $document['ENTRIES'][$index]['SUPPLIES_COMMAND']     = $command;
                }
            }
        }
        return $ok;
    }


    /**
     *  Bulk update a table with fields
     *
     *      Example: update DOCENTRYMST with one or a couple of columns with a bunch of rows.
     *
     * for example,
     *      $sets       can be something like "qtywithvalue = :2(i), qtyonhand = :2(i), extendedcost = :3(i)"
     *      $where      can be something like "cny# = :1(i) and record# = :4(i)"
     *      $dataTypes  can be something like [ "integer", "decimal", "decimal", "integer" ]
     *                      (in the right order)
     *
     * @param string        $table                  Table name, like DOCENTRYMST
     * @param string        $sets                   the set statements with parameter placeholders (see above)
     * @param string        $where                  The where clause with parameter placeholders (see above)
     * @param string[]      $dataTypes              Data types for each place holder above, like 'integer', 'varchar'
     * @param array         $valuesArray            the array of arrays
     *
     * @return bool
     */
    private function bulkUpdate( $table, $sets, $where, $dataTypes, $valuesArray )
    {
        if (empty($valuesArray)) {
            return true;
        }

        $qry        = [];
        $qry[]      = "UPDATE $table SET $sets WHERE $where ";
        $qry[]      = $valuesArray;
        $qry[]      = $dataTypes;

        return ExecBulkStmt($qry);
    }


    /**
     *      Since we can't / don't use 'real' CONVERSION code, we instead cross-link the Supplies Request to
     *  the target documents, like an Issue, PO, Direct-ship PO, Warehouse Transfer, etc.
     *
     *      The general process of saving this pseudo-convertde documet is:
     *
     *          1) Save the links to the source document in the target document BEFORE EntityManager save (add/update)
     *                  setLinksInRequest(), above
     *          2) Start a transaction (can do that before (1) if desired)
     *          3)      EntityManager::regularAdd() or regularSet()
     *          4)      Call this to update the source document (the set of Supply Requisition lines) (yes, AFTER the save)
     *          5) Complete the transaction (commit/abort)
     *
     *  this function is step 4.
     *
     *  Note about deleting: when deleting a record, call this with '$targetIsBeingDeleted' true, and that 'de-links'
     *                       the source records.
     *                          If you are deleting a Supply Request, call this with the document
     *                              as the request and it will de-link any issues, transfers, POs, whatever.
     *                          If you are deleting a PO, Issue, other-non-request, call this with the deleting document
     *                              and any request documents will be de-linked.
     *
     * @param array     $document               The TARGET document, like the Issue or PO (not the Supplies Requisition)
     * @param bool      $targetIsBeingDeleted   Is the TARGET being deleted?
     *
     * @return bool                             DB ok?
     */
    private function crossLinkSourceToTarget($document, $targetIsBeingDeleted = false)
    {
        $ok = true;
        if ( ! empty($document['ENTRIES'])) {
            $cny         = GetMyCompany();
            $updateArray = [];
            $links       = [];

            // get the source record numbers....
            $records  = [];
            foreach ($document['ENTRIES'] as $index => $row) {

                if ($targetIsBeingDeleted) {
                    // documents may not HAVE any links, for example in the delete case
                    if (($row['SUPPLIESSTATUSDETAIL'] ?? '') == '') {
                        continue;   // simplify the 'no links' case with a quick exit
                    }

                    // track all of the OTHER docentries for the links....
                    $suppliesDetails = self::getSuppliesDetails($row);

                    foreach ($suppliesDetails as $detailRow) {
                        $requestRecord              = $detailRow['RECORDNO']; // the OTHER docentry
                        $records[$requestRecord]    = false; // we want to fetch this (and remove dups)
                        $links[]                    = ['LINK' => $detailRow, 'DOCENTRY_INDEX' => $index];
                    }

                    // not the delete case, so make sure this is a supplies item and we know the command
                } else if ($row['SUPPLIESITEM'] && ($row['SUPPLIES_COMMAND'] !== '')) {

                    $targetDirty     = false;
                    $suppliesDetails = self::getSuppliesDetails($row);

                    foreach ($suppliesDetails as $foundAt => $detailRow) {

                        // take everything; if it had been updated in the source doc, we just check the quantity...
                        $requestRecord           = $detailRow['RECORDNO']; // the OTHER docentry
                        $records[$requestRecord] = false; // we want to fetch this (and remove dups)
                        $links[]                 = ['LINK' => $detailRow, 'DOCENTRY_INDEX' => $index];

                        // did the human change the quantity on the current form?
                        //    If so we need to update the quantity on the other side too
                        $quantityNow     = $row['QUANTITY'];
                        $quantityPlanned = $detailRow['QUANTITY'];
                        if ($quantityNow != $quantityPlanned) {
                            $suppliesDetails[$foundAt]['QUANTITY'] = $quantityNow;
                            $targetDirty = true;
                        }
                    }

                    if ($targetDirty) {
                        $thisRecord = $row['RECORDNO'];  // target record#, like the ISSUE or PO
                        $updateArray[] = [$cny, $thisRecord, self::setSuppliesDetails($suppliesDetails)];    // ORDER IS IMPORTANT
                    }
                }
            }

            // Nothing to do?
            if (empty($records)) {
                return true;
            }

            // Now get the source (request) STATUSDETAIS....
            $list = $this->GetList([  // we are a document entry derivitive
                'selects'       => ['SUPPLIESSTATUSDETAIL', 'RECORDNO'],
                'filters'       => [[['RECORDNO', 'in', array_keys($records)]]],
                'usemst'        => true
            ]);

            // Index the list we just read by the REQUEST's record#
            $sourceStatusDetails = [];
            if ( ! empty($list)) {
                foreach ($list as $row) {
                    // note: new supplies requests may have an empty/null supplies status detail, and so aren't here!
                    $sourceStatusDetails[ $row['RECORDNO'] ] = self::getSuppliesDetails(['SUPPLIESSTATUSDETAIL' => ($row['SUPPLIESSTATUSDETAIL'] ?? '')]);
                }
            }

            // Now iterate over the rows and process each status field and save it.
            // if we are deleting, remove any trace of this command
            // otherwise update the OTHER document to point to THIS document
            $today = GetCurrentDate();
            foreach ($links as $link) {
                $statusDetails      = $link['LINK'];
                $indexOfDocentry    = $link['DOCENTRY_INDEX'];    // in THIS document
                $requestRecord      = $statusDetails['RECORDNO']; // the OTHER docentry
                $requestCommand     = $statusDetails['COMMAND'];  // the command there
                $quantity           = $document['ENTRIES'][$indexOfDocentry]['QUANTITY'];    // current quantity
                $targetDocEntry     = $document['ENTRIES'][$indexOfDocentry]['RECORDNO'];
                $foundAt            = self::suppliesDetailsHasCommand($sourceStatusDetails[$requestRecord], $requestCommand, $targetDocEntry); // points to me
                // if found, we may want to update the quantity
                // (maybe customer updated the txn, maybe they're deleting)
                if ($foundAt !== false) {
                    if ($targetIsBeingDeleted) {
                        // when deleteing, REMOVE this entry from the source's array
                        unset($sourceStatusDetails[$requestRecord][$foundAt]);
                        $records[$requestRecord] = true;    // this one is 'dirty'
                    }
                } else if (! $targetIsBeingDeleted) {   // don't bother ADDING if we're deleting this target
                    // but if NOT found we want to add it
                    // update the REQUEST status to include a reference to the issue/po/transfer/whatever
                    $records[$requestRecord] = true;    // this one is 'dirty'
                    self::addCommandToSuppliesDetails(  $sourceStatusDetails[$requestRecord],
                                                $requestCommand, $targetDocEntry, $quantity, $today);
                }
            }

            // put back the requests
            foreach ($sourceStatusDetails as $requestRecord => $ssd) {
                if ($records[$requestRecord] === true) {  // dirty?
                    $updateArray[] = [$cny, $requestRecord, self::setSuppliesDetails($ssd)];    // ORDER IS IMPORTANT
                }
            }

            // bulk update any records we found (even if only one) (routine checks for empty array)
            $ok = $this->bulkUpdate('docentrymst',
                                        "supplieslinesource = :3(i) ",   // internal name of SUPPLIESSTATUSDETAIL
                                        "cny# = :1(i) AND record# = :2(i) ",
                                        ['integer', 'integer', 'char'],
                                        $updateArray); // values must be in the 1, 2, 3 order!
        }
        return $ok;
    }


    /**
     *  After saving a converted supplies document, call this to update the source requests.  This occurs inside
     * a transaction, so if the txn fails these updates don't happen.
     *
     *  When deleting, we need to back out any changes to the sources
     *
     * @param array     $document   The document tree AFTER saving (so it has the record#s)
     *
     * @return bool
     */
    public function conversionSaved( & $document )
    {
        $ok = $this->crossLinkSourceToTarget($document, false);
        return $ok;
    }


    /**
     *  When any document is being deleted, if it had any trace of links to other documents,
     *  remove those links from the other documents.
     *
     *  For example: delete a PO.  Maybe it had links from Supply Requests waiting on the PO
     *               delete an issue.  Maybe it had links from several Supply requests
     *               delete an issue-return.  Remove links from the issue.
     *
     * @param array     $document       Document object
     *
     * @return bool
     *
     */
    public function documentIsBeingDeleted( & $document)
    {
        $ok = $this->crossLinkSourceToTarget($document, true );
        return $ok;
    }


    /**
     *  Get the supplies history, if any.  This is for forms to show the supplies history on the HISTORY tab.
     *  For example, on a PO, it will show all the supply requests linked to it.
     *
     * @param array     $document   Document tree
     *
     * @return array                Array of ITEMID, DOCID, LINENO, QUANTITY, or empty
     */
    public function suppliesHistory( $document )
    {
        // *******************
        // ***** HELPERS *****
        // *******************

        /** @var callable $getSuppliesLinks */
        $getSuppliesLinks = function($document) {
            $getThese = [];
            if (isset($document['ENTRIES'])) {
                foreach ($document['ENTRIES'] as $row) {
                    // documents may not HAVE any links, for example in the delete case
                    if (($row['SUPPLIESSTATUSDETAIL'] ?? '') == '') {
                        continue;   // simplify the 'no links' case with a quick exit
                    }
                    $suppliesDetails = self::getSuppliesDetails($row);
                    foreach ($suppliesDetails as $detailRow) {
                        $record    = $detailRow['RECORDNO'];
                        $getThese[$record][] = $detailRow;
                    }
                }
            }
            return $getThese;
        };

        /** @var callable $getRecords */
        $getRecords = function($getThese) {
            $rtn = [];
            if ( !empty($getThese)) {
                $list = $this->GetList([
                    'selects'       => [ 'RECORDNO', 'ITEMID', 'ITEMNAME', 'DOCID', 'LINE_NO', 'EMPLOYEEID', 'EMPLOYEENAME', 'SALE_PUR_TRANS' ],
                    'filters'       => [[['RECORDNO', 'in', array_keys($getThese)]]],
                    'usemst'        => true
                ]);
                if ($list === false) {
                    return false;
                }
                foreach ($list as $row) {
                    $row['ITEM'] = $row['ITEMID'] . '--' . ($row['ITEMNAME'] ?? '');
                    $row['EMPLOYEE'] = " ";
                    if (isset($row['EMPLOYEEID']) && ($row['EMPLOYEEID'] != '')) {
                        $row['EMPLOYEE'] = $row['EMPLOYEEID'] . '--' . ($row['EMPLOYEENAME'] ?? '');
                    }
                    //$row['LINE_NO']     = ($row['LINENO'] ?? 0) + 1;
                    $recordNo           = $row['RECORDNO'];
                    $row['SPI']         = $row['DOCPARAMETER.SALE_PUR_TRANS'];
                    $row['SUPPLYDOCUMENT'] = $row['DOCID'];
                    $row['LINE_NO']++;

                    // get rid of things we used to assemble item and employee
                    unset($row['ITEMID'], $row['ITEMNAME'], $row['EMPLOYEEID'], $row['EMPLOYEENAME'], $row['RECORDNO'],
                            $row['DOCPARAMETER.SALE_PUR_TRANS'], $row['DOCID']);

                    $rtn[$recordNo] = $row;
                }
            }
            return $rtn;
        };

        // *******************
        // **** MAIN CODE ****
        // *******************
        $rtn = [];

        $getThese = $getSuppliesLinks($document);
        $list     = $getRecords($getThese);

        $textMap  = getLocalizedText(I18N::tokenArrayToObjectArray(['IA.NO' , 'IA.YES']), $error);
        $no       = $textMap['IA.NO'];
        $yes      = $textMap['IA.YES'];

        foreach ($list as $recordNo => $row) {
            foreach ($getThese[$recordNo] as $details) {
                $command = $details['COMMAND'];
                $completed = (substr($command, 0, 1) === self::STATUSDETAILS_COMPLETED); // format: Xcommand
                if ($completed) {
                    $command = substr($command, 1); // trim off the X
                }
                $row['QUANTITY'] = $details['QUANTITY'];
                $row['ACTIVE'] = $completed ? $no : $yes; // note ACTIVE is the opposite of COMPLETED
                $row['STATUS'] = $this->internalToExternalStatus($command);
                $row['DATE'] = $details['DATE'] ?? '';
                $rtn[] = $row;
            }
        }
        return $rtn;
    }


    /**
     * Supplemental function for supplies printing; call from
     *      either InvSuppliesEditor or InvDocumentFormEditor
     *
     * Public so it can be calld from outside
     *
     * @param array     $values     Object details
     *
     */
    public function prepareDataForPrinting(&$values)
    {
        $records = $values['RECORDS'] ?? [];

        if (empty($records)) {
            $keep = $values['LINES'];
        } else {
            $records = $this->sanitizeRecordNumbers($records);
            $lines = $values['LINES'];
            $keep = [];
            foreach ($lines as $row) {
                if (in_array($row['RECORDNO'], $records)) {
                    $keep[] = $row;
                }
            }
        }
        if (empty($keep)) {
            // well, get them all then
            $keep = $this->getListOfSupplyItems($records);
        }
        $textMap  = getLocalizedText(I18N::tokenArrayToObjectArray(['IA.NONE']), $error);
        $none     = $textMap['IA.NONE'];

        $entries  = [];
        foreach ($keep as $row) {
            $warehouse = $row['WAREHOUSE'];
            if (trim($warehouse) == '') {
                $row['WAREHOUSE'] = $none;
            }
            unset($row['LINEACTIONS']);
            $entries[] = $row;
        }

        // put in warehouse/item order
        usort($entries, function($a,$b) {
            $cmp = strcmp($a['WAREHOUSE'], $b['WAREHOUSE']);
            if ($cmp === 0) {
                $cmp = strcmp($a['ITEMID'], $b['ITEMID']);
                if ($cmp === 0) {
                    $cmp = strcmp($a['EMPLOYEE'], $b['EMPLOYEE']);
                    if ($cmp === 0) {
                        $rnA = $a['RECORDNO'];
                        $rnB = $b['RECORDNO'];
                        $cmp = ($rnA < $rnB) ? -1 : (($rnA > $rnB) ? +1 : 0);
                    }
                }
            }
            return $cmp;
        });

        // This is the R2 EA format; likely folks will want MORE for GA....
        unset($values['LINES']);
        $values['ENTRIES'] = $entries;

    }


    /**
     * Code to generate output from a Word Template.....
     *
     * Normally this is in an Editor, but I want access from InvSuppliesEditor AND InvDocumentFormEditor
     *
     * This is for EA, not GA; likely we'll want user-created forms and more data....
     *
     * @param array         $dataForPrinting    from Editor::GetDataForPrinting()
     * @param bool          $forPicklist        if true, use the picklist template; otherwise the general report template.
     *
     * @return bool
     */
    public function printSuppliesReport($dataForPrinting, $forPicklist)
    {
        //  If tracking access, mark it as for print.
        AdvAuditTracking::setOperation(AuditTrail::OPID_PRINT);
        $dataForPrinting['WHENCREATED'] = GetCurrentDate(IADATE_USRFORMAT);
        $dataForPrinting['COMPANY']['NAME'] = GetMyCompanyName();
        $xml    = XMLUtils::BuildWSXML($dataForPrinting);

        // if you have multiple rows, the $dataForPrinting will have an underscore before the key values in the array, so
        // lets remove them here.  This is because we're doing multiple documents back to back, one per warehouse.
        $xml    = str_replace('<key>_', '<key>', $xml);


        // ******************************************************************************************
        // borrowed from DocumentFormEditor for now, eventually we'll want to get this template from
        // the 'xslformat' manager if we can....
        // ******************************************************************************************

        // this should be replaced by something like GetTemplateType() in Document Form Editor;
        // and maybe this is a backup in case the user hasn't entered one.....
        $picklistTemplate   = $forPicklist
                            ? 'supplies_pick_template.docx'
                            : 'supplies_report_template.docx';

        $fileContentStr   = file_get_contents($picklistTemplate, true);
        if ($fileContentStr === false) {
            LogToFile('Cannot find/read supplies_pick_template.docx');
            return false;
        }

        // for now....
        $langCode    = 'en';
        $countryCode = 'US';
        $template    = $fileContentStr;

        $params = [
            'LANGCODE'     => $langCode,
            'COUNTRYCODE'  => $countryCode,
            'WHENMODIFIED' => GetCurrentDate(IADATE_USRFORMAT),
            'ENCRYPTPDF'   => 'F',
            'OUTPUTTYPE'   => 'PDF',
        ];
        $out = genPDFFromWORD($xml, $template, true, $params); // false means dump the PDF to the current stream
        if ($out === false) {
            return false;
        }
        return true;
    }

}
