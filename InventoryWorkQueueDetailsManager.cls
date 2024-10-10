<?


class InventoryWorkQueueDetailsManager extends OwnedObjectManager   // parent is InventoryWorkQueue
{
    /** @var DocumententryTrackDetailManager|null  $deTrackManager */
    protected $deTrackManager = null;


    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
        $this->deTrackManager = Globals::$g->gManagerFactory->getManager('documententrytrackdetail');
    }


    /**
     *      Handle common code for add and set
     *
     * @param array $values         stuff to add or set, may be bulk
     *
     * @return bool
     */
    protected function regularAddOrSet(&$values)
    {
        // we may get an array of values, or a single value.
        //  This is what the Entity Manager does.....
        if (empty($values)) {
            return true;    // someone had an empty array when saving, which is ok
        }
        if (!isset($values[0]) || !is_array($values[0])) {
            $groupOfValues[0] = &$values;
        } else {
            $groupOfValues = &$values;
        }

        $currentDate    = $this->getTimestampGMT(); // Get current sysdate with time in GMT
        $currentUserRec = GetMyUserid();     // Get the logged in user record no
        $addThese       = [];
        $setThese       = [];
        $ok             = true;
        foreach ($groupOfValues as $groupIndex => $oneValue) {
            // do some validation from the document entry track details manager...
            if ($this->deTrackManager->hasTrackingDetails($oneValue)) {
                $ok = $ok && $this->deTrackManager->prepValues($oneValue);

                // a little name confusion here between us and the documententrytrackdetail records
                if (isset($oneValue['QUANTITYPICKED']) && ! isset($oneValue['QUANTITYALLOCATED'])) {
                    $oneValue['QUANTITYALLOCATED'] = $oneValue['QUANTITYPICKED'];
                } else if (isset($oneValue['QUANTITYALLOCATED']) && ! isset($oneValue['QUANTITYPICKED'])) {
                    $oneValue['QUANTITYPICKED'] = $oneValue['QUANTITYALLOCATED'];
                }

                // we're not audited and have no trigger, so.....
                // irrespective of creating or updating object, always set modifieddate and modifiedby
                $oneValue[':whenmodified'] = $currentDate;
                $oneValue[':modifiedby']   = $currentUserRec;
                if (($oneValue['WHENCREATED'] ?? null) == null) {
                    $oneValue[':whencreated'] = $currentDate;
                    $oneValue[':createdby'] = $currentUserRec;
                }


                // trust track_quantity over quantity; empirically seems like they should be this way
                $quantity                      = ($oneValue['TRACK_QUANTITY'] ?? ($oneValue['QUANTITY'] ?? 0));
                $oneValue['QUANTITY']          = $quantity;
                $oneValue['TRACK_QUANTITY']    = $quantity;   // so they are the same

                // yet-another quirk of having THREE owners to an object:
                // docentry, say, may have added this record, and now we are
                // ADDING a work queue record, and it's tracking already exists,
                // but the Entity Manager assumes if you are adding a record, you
                // must be ADDING all the owned objects!  Not so in this case!
                $oneValue['GROUP_INDEX'] = $groupIndex;
                if (isset($oneValue['RECORD#']) || isset($oneValue['RECORDNO'])) {
                    $setThese[]  = $oneValue;
                } else {
                    $addThese[]  = $oneValue;
                }
            }
        }

        if ( ! empty($addThese)) {
            $ok = $ok && parent::regularAdd($addThese);
            foreach ($addThese as $oneValue) {
                $groupIndex = $oneValue['GROUP_INDEX'];
                $groupOfValues[$groupIndex] = $oneValue;   // put it back in case caller wants record# and the like
            }
        }

        if ( ! empty($setThese)) {
            $ok = $ok && parent::regularSet($setThese);
            foreach ($setThese as $oneValue) {
                $groupIndex = $oneValue['GROUP_INDEX'];
                $groupOfValues[$groupIndex] = $oneValue;   // ditto
            }
        }
        return $ok;
    }


    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        return $this->regularAddOrSet($values);  // true means 'add'
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        return $this->regularAddOrSet($values);  // false means 'set'
    }


    /**
     * Get a single record.
     *
     *
     * @param string        $recordNum          A record# (of the inventory work queue record
     * @param string[]|null $fields
     *
     * @return array|false                      one DETAIL LINE
     */
    function get($recordNum, $fields = null)
    {
        $record = parent::get($recordNum, $fields);

        if (($record !== false) && (!empty($record))) {
            // a little name confusion here between us and the documententrytrackdetail records
            // so be more forgiving with code dealing with either
            $record['QUANTITYALLOCATED'] = $record['QUANTITYPICKED'] ?? 0;
        }
        return $record;
    }


    /**
     * Override the Entity Manager GetList() code.
     *
     *
     * @param array $params    a structure used to build the custom query
     * @param bool  $_crosscny if true do not add the var.cny# = ... code
     * @param bool  $nocount   don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        if ( ! InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            return [];
        }
        $return = parent::GetList($params, $_crosscny, $nocount );   // DO THE QUERY (cross your fingers!)
        if ($return !== false) {
            foreach ($return as $index => $row) {
                // a little name confusion here between us and the documententrytrackdetail records
                // so be more forgiving with code dealing with either
                $return[$index]['QUANTITYALLOCATED'] = $row['QUANTITYPICKED'] ?? 0;
            }
        }
        return $return;
    }


    /**
     *      When the tracking handler is looking at serial numbers, it gets a list of available numbers,
     *  and sees if a transaction is using only those.  I.e. it wants to find out which SN's are available
     *  to the current document.
     *
     * @param string    $itemID             The item in question (regardless of warehouse)
     * @param array     $availableSNs       The currently available SN's in an array with field 'SERIALNO'
     *
     * @return bool                         Did it work (were there DB errors)?
     */
    public static function allocatedSerialNumbers($itemID, & $availableSNs)
    {
        // Do I even EXIST?
        if ( ! InventoryWQOrderManager::featureEnabled(InventoryWQOrderManager::FEATURE_FLAG_ONLY)) {
            return true;   // feature not here, so nothing allocated
        }

        if (($availableSNs !== null) && !empty($availableSNs)) {
            $sn = [];
            foreach ($availableSNs as $index => $row) {
                $oneSn = $row['SERIALNO'] ?? 0;
                if ($oneSn) {
                    $sn[$oneSn] = $index;
                }
            }

            if (!empty($sn)) {
                $sql   = [];
                $sql[] = "SELECT    SERIALNO
                            FROM    V_INVTRACKINGALLOCATED
                            WHERE   cny# = :1 AND itemid = :2 ";
                $sql[] = GetMyCompany();
                $sql[] = $itemID;
                $sql   = PrepINClauseStmt($sql, array_keys($sn), ' and SERIALNO ');
                $rtn   = QueryResult($sql);
                if ($rtn === false) {
                    return false;
                }
                foreach ($rtn as $row) {
                    $oneSn = $row['SERIALNO'];
                    unset($availableSNs[$sn[$oneSn]]);  // nope, not available, because I got it!
                }
            }
        }
        return true;
    }

}

