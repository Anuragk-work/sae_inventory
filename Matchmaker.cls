<?php

/**
 * FILE: Matchmaker.cls
 * AUTHOR: Roger Collins
 * DESCRIPTION: Tries to match existing records (with a record#) to newly-constructed records, but without a record#.
 *
 * (C) 2019, Sage Intacct Corporation, All Rights Reserved
 *
 * This document contains trade secret data that belongs to Sage Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Sage Intacct Corporation.
 */


//  *************************************************************************
//  *************************************************************************
//  Matchmaker
//
//      Here's the idea:
//
//          There's a BUNCH of code that constructs records to be added,
//      such as DocEntryCost records, where the assumption was that the OLD
//      DocEntryCost records (for example) were deleted.
//
//          We would rather just UPDATE the records if we can, and NOT
//      delete/add them (we want to 'upsert').
//
//          But the code creating the records doesn't know about the old records,
//      and specifically doesn't know the old RECORD#, if there was one.
//      So, THIS class tries to help.....
//
//      In an ADD scenario (new transaction):
//      Call the matchmaker to see if there are matches to old records,
//      there WON'T be, so add the records as we always did before.
//
//      In an UPDATE (Set()) scenario (some existing records):
//      Call the matchmaker ONCE to get the existing records,
//      Then call the matchmaker for each 'new' record to see if it matches
//      an existing record.  If it does, then Matchmaker will do an update.
//      if it does not (just like in the ADD scenario above), then the
//      caller does an add.
//
//      When done, tell the Matchmaker you're done and it will DELETE any
//      old entries that shouldn't exist anymore.
//
//      In other words:
//
//      1) Create matchmaker, give it your entity manager
//      2) Get existing records for the parent
//      3) For each 'new' record (constructed by business logic),
//          4) Call the matchmaker
//          5) It will add/set the new item (and is conservative, so if it doesn't match it adds new)
//      6) Tell the matchmaker you're done (so it can delete records not relevent anymore)
//
//
//      A note about the matching:
//          a) there is a list of fields that don't have to match from an existing record, such as CNY#
//              and 'WHOCREATED' and the like.  There is a default list of these, clients can add more.
//              the idea is that someone creating a new record in memory won't bother to fill those in.
//
//          b) there is a list of fields that constitute a match; these are the
//              'match' fields.  For example, DOCHDR or DOENTRY or ITEMID; references to the owner or parent object
//
//
//      NOTE: DANGER
//          This matchmaking table won't be infallible, and may delete and add perfectly good entries.  Therefore,
//          it is important that you upsert tables IN ORDER so that a table that depends on another table is upserted
//          after that other table.  For the DocumentManager, for example, it uses DocumentManager::updatingEntity()
//          to track this....
//
//  *************************************************************************
//  *************************************************************************

class Matchmaker
{
    const       DEBUGGING           = true;     // outputs more text to the log

    const       USE_ADD             = 1;        // use add() to add this new record
    const       USE_SET             = 2;        // update the record with set()
    const       IGNORE_IDENTICAL    = 3;        // ignore this identical record (no add/no set)

    // helpers for the constructor, so you don't have to pass TRUE, FALSE over and over again:
    const       DONT_ALLOW_IGNORE   = true;
    const       ALLOW_IGNORE        = false;
    const       DELETE_BY_RECORDNO  = true;
    const       DELETE_BY_ENTITY_MANAGER = false;

    // due to the random bugs in things like deglresoves, which don't have record#s,
    // I decided to be more conservative: now we match entirely everything, or we
    // delete/create (as before upsert)
    const       BE_CONSERVATIVE     = true;     // true means match everything, don't use the match criteria.  False means use the match criteria


    const       COMMON_IGNORE_FIELDS = [
        'CNY#', 'RECORD#', 'RECORDNO',
        'WHENCREATED', 'WHENMODIFIED', 'CREATEDBY', 'MODIFIEDBY',
    ];


    /** @var EntityManager $entityManager  */
    public      $entityManager;

    /** @var string[]      $matchFields           the list of fields that constitute a match. */
    private     $matchFields;

    /** @var string[] $ignoreFields               the list of fields we ignore on an existing record. */
    private     $ignoreFields;

    /** @var array $currentEntries                existing entries, from getCurrentRecords() or getCurrentRecordsByParent() */
    private     $currentEntries;

    /** @var string $recordNoFieldName            what is the name of the record# field?  Sometimes RECORDNO, sometimes RECORD# */
    private     $recordNoFieldName;

    /** @var bool $setEvenIfNoChange              even if the record is exactly the same, go ahead and Set() it, don't ignpre it.
     *                                            For example, if you need triggers to fire or WHENCHANGED to be set.
     */
    private     $setEvenIfNoChange = false;

    /** @var bool $deleteByRecordNo               some EntityManagers are sorta broken and Delete() doesn't just delete one record. */
    private     $deleteByRecordNo;

    /** @var bool $dupMatchesAreOk                for most records, there's a risk that we match against record A when B also matches.  Do we care for THIS entity? */
    private     $dupMatchesAreOk = false;

    /** @var array $useOwnedObjectList            which owned objects, if any, do we care about?  */
    private     $useOwnedObjectList = [];

    /** @var array $nullIsThisValue               when comparing a new field, if it is null, assume it is <this value> */
    private     $nullIsThisValue = [];          // key is field name, value is the value, like 'false'.

    /** @var bool $matchWithMatchFields */
    private     $matchWithMatchFields;          // even if conservative mode is on, do we only match with the match fields?



    /**
     *  Set up a 'match maker' for one entity manager instance
     *
     * @param  EntityManager $entityManager         the entity manager instance this match maker is working for
     * @param  bool          $setEvenIfNoChange     use Set() even when a record has not changed (to fire triggers, for example)
     * @param  bool          $deleteByRecordNo      When deleteing, do it by hand and by record #, don't use the EntityManager::Delete()
     * @param string[]       $matchFields           the list of fields that constitute a match; defaults to the list
     *                                              in the .ent file called 'matchmaker_match_fields', or in
     *                                              DocumentManager::MATCHMAKER_MATCH_FIELDS.
     * @param  string[]      $ignoreFields          the list of fields that are ignored in an existing record.  This adds
     *                                              on to the default list (of CNY#, RECORD#, ...)
     * @param bool           $matchDimentions       Should we match dimensions?  usually true
     */
    function __construct($entityManager, $setEvenIfNoChange = false, $deleteByRecordNo = false, $matchFields = [], $ignoreFields = [], $matchDimentions = true)
    {
        if (($entityManager == NULL) || !($entityManager instanceof EntityManager)) {
            throw new Exception("[Code bug] Creating a 'Matchmaker' instance without an EntityManager.");
        }
        $this->nullIsThisValue   = [];
        $this->entityManager     = $entityManager;
        $this->matchFields       = $matchFields ?? [];
        $this->setEvenIfNoChange = $setEvenIfNoChange;
        $this->deleteByRecordNo  = $deleteByRecordNo;
        $objectList              = $entityManager->_schemas[$entityManager->_entity]['object'] ?? [];
        $this->recordNoFieldName = in_array('RECORDNO', $objectList) ? 'RECORDNO' : (in_array('RECORD#', $objectList) ? 'RECORD#' : '');
        $this->matchWithMatchFields = false;

        // Does the .ent file have specific edit fields for us to use?
        if (isset($entityManager->_schemas[$entityManager->_entity]['matchmaker_match_fields'])) {
            $this->matchFields   = array_merge($this->matchFields, $entityManager->_schemas[$entityManager->_entity]['matchmaker_match_fields']);
        }
        // does the document manager describe the match fields?
        if (isset(DocumentManager::MATCHMAKER_MATCH_FIELDS[$entityManager->_entity])) {
            $this->matchFields   = array_merge($this->matchFields, DocumentManager::MATCHMAKER_MATCH_FIELDS[$entityManager->_entity]);
        }

        if (empty($this->matchFields)) {
            throw new Exception("Creating a 'Matchmaker' instance without list of fields to match.");
        }

        // fields to ignore.  There's a constnat list above, and the caller may pass IN some ignore fields.
        //  Finally, there is no point in trying to match 'child' fields, of the schema format 'class.name', like
        //  'users.name' for 'whocreated', say
        $this->ignoreFields = array_merge(self::COMMON_IGNORE_FIELDS, $ignoreFields); // ignore these in existing records
        // these were for a different purpose and don't work for us, so don't use 'em!
        // ('ignore' meant 'if these don't match you can still upsert rather than post')
        // $this->ignoreFields = array_merge($this->ignoreFields, array_map('strtoupper', $entityManager->getIgnoreFields()));
        $schema = $this->entityManager->_schemas[$this->entityManager->_entity]['schema'];
        $childFIelds = [];
        foreach ($schema as $externalField => $internalField) {
            // some schemas have arrays for things like contacts; these are read-only in practice
            // and don't bother with read-only child fields, like 'user.name'
            if (is_array($internalField) || (strpos($internalField, '.') !== false)) {
                $childFIelds[] = $externalField;    // get the external field to compare and ignore
            }
        }
        $this->ignoreFields      = array_merge($this->ignoreFields, $childFIelds);

        if ($matchDimentions) {
            // add dimensions to the match keys.
            // if neither record HAS dimensions, well then they both compare as empty/null, so they match :-)
            $this->matchFields = array_merge($this->matchFields, IADimensions::GetDimensionKeys());

            // lets merge custom dimension string as well
            if (IADimensions::isCustomDimensionsEnabled()) {
                $cust_dim_fields = GLEntryManager::getPTFieldsMap();
                if ($cust_dim_fields) {
                    foreach ($cust_dim_fields as $field) {
                        $this->matchFields[] = $field;
                    }
                }
                // $this->matchFields[] = 'CUSTOMDIMENSIONS';  // this is the holder for all custom dimensions
            }
        }

        // No current sql entries yet
        $this->currentEntries = [];

        // Will we be dealing with owned objects?  (not often)
        $ownedList = $this->entityManager->_schemas[$this->entityManager->_entity]['ownedobjects'] ?? [];
        foreach ($ownedList as $owned) {
            $mgr = Globals::$g->gManagerFactory->getManager($owned['entity']);
            // only if we can figure out what the match fields are.....
            if (isset($mgr->_schemas[$mgr->_entity]['matchmaker_match_fields']) || isset(DocumentManager::MATCHMAKER_MATCH_FIELDS[$mgr->_entity])) {
                $this->useOwnedObjectList[$owned['entity']] = $owned;
            }
        }
    }


    /**
     * @param string    $field              the field name, like 'SC_EXTENDLINEPERIOD'
     * @param mixed     $nullIsThisValue    the value to assume when the new value is null
     */
    public function setNullMeans( $field, $nullIsThisValue )
    {
        $this->nullIsThisValue[ $field ] = $nullIsThisValue;
    }


    /**
     *      Often, matching is conservative where we match the entire schema, just to be sure.
     *  In some cases, like AR/AP PrRecordEntries, we want the simpler 'match fields' match
     *
     * @param bool $on
     */
    public function matchWithMatchFieldsOnly($on = true)
    {
        $this->matchWithMatchFields = $on;
    }


    /**
     *      Most entities the actual record match matters; you don't want to assign a new record to an
     *  existing one poorly in case another record refers to this one.  But, if that is NOT the case for
     *  your entity, you can set this to TRUE and dups will be fine; we'll take the best match we can.
     *
     * @param bool  $dupMatchesAreOk        if we match duplicates, does it matter which one to take?
     */
    public function setDupMatchesAreOk($dupMatchesAreOk)
    {
        $this->dupMatchesAreOk = $dupMatchesAreOk;
    }


    /**
     *      For most records, the record number IS the 'primary key' or best way of fetching/deleting
     * but for some records, such as 'deglsubtotresolve' there is no record number.  In that case, we use
     * the concatenation of the MATCH fields.
     *
     *  This routine returns an array of fields to use as the 'primary key' for an existing record.
     * USUALLY this will be the record number field.
     *
     * @param  bool      $internal        use the internal name rather than the external name?
     *
     * @return string[]                   the list of fields to use as the 'primary key'
     */
    protected function getPrimaryKeyFields($internal = false)
    {
        $recordNames   = [];
        $recordNames[] = $this->recordNoFieldName;
        // this is NOT the normal case
        if ($this->recordNoFieldName == '') {
            $recordNames = $this->matchFields;
        }

        if ($internal) {
            $schema            = $this->entityManager->_schemas[$this->entityManager->_entity]['schema'];
            foreach ($recordNames as &$externalField) {
                if (isset($schema[$externalField])) {
                    $internalField  = $schema[$externalField];
                    $externalField  = $internalField;
                }
            }
        }
        return $recordNames;
    }


    /**
     *      For most records, the record number IS the 'primary key' or best way of fetching/deleting
     * but for some records, such as 'deglsubtotresolve' there is no record number.  In that case, we use
     * the concatenation of the MATCH fields.
     *
     * @param array   $rec              the record to look at
     * @param  bool   $internal         use the internal name rather than the external name?
     *
     * @return string                   the value of the key/vid/record#
     */
    protected function getPrimaryKeyValues($rec, $internal = false)
    {
        $fields = $this->getPrimaryKeyFields($internal);
        $rtn    = '';
        foreach ($fields as $field) {
            $rtn .= $rec[$field] ?? '';
        }
        return $rtn;
    }


    /**
     *      Get the list of fields to read from a table, in order, suitable for the Entity Manager
     *  The entity manager converts fields from external to internal format assuming the same order
     *  was fetched as are listed in the entity file's OBJECT list.
     *
     * @return string
     */
    protected function getSelectList()
    {
        global $kTables;
        $tableName  = $this->entityManager->_schemas[$this->entityManager->_entity]['table'] ?? '';
        $fieldTypes = $kTables[$tableName]['db_fieldinfo'] ?? [];
        $timestampFields = [];
        // find any timestamp fields
        foreach ($fieldTypes as $fieldName => $type) {
            if (($type['type'] ?? '') === 'timestamp') {             // dates don't seem to need special handling.
                $timestampFields[$fieldName] = true;                // the field name is in lower case here
            }
        }

        $selectList = [];
        $externalListToGet = $this->entityManager->GetGetFields();
        $schema            = $this->entityManager->_schemas[$this->entityManager->_entity]['schema'];

        foreach ($externalListToGet as $externalField) {
            if (isset($schema[$externalField])) {
                $internal = $schema[$externalField];
                if (isset($timestampFields[$internal])) {
                    $selectList[] = "to_char($internal, 'MM/DD/YYYY HH24:MI:SS')";

                // and don't bother with read-only child fields, like 'user.name'
                    // nor with fields that are arrays (like 'DOCUMENT' => array('document.*' => 'document.*'))
                } else if (( ! is_array($internal)) && (strpos($internal, '.') === false)) {
                    $selectList[] = $internal;    // get the internal field to get, like RECORD# from RECORDNO
                }
            }
            // else, the external field may have a dot in it, like 'WAREHOUSE.LOCATION_NO'
        }
        return implode(',', $selectList);
    }


    /**
     *      Get any current records, by parent key and parent name
     *  This gets the current entries, for example for a DocEntryCost table, where there is no owner relationship.
     *  Note that this requires that there is JUST ONE parent field (CNY# is also assumed).
     *
     * This is used instead of GetByParent() when there is no owner/owned relationship
     *
     * If you CAN, it would be better to use getCurrentRecordsByParent(), above.
     *
     * @param string    $parentName         The name of the parent field, like 'DOCENTRYKEY'
     * @param string    $parentKey          The value of the parent field, like '123'
     *
     * @return bool               The current entries, or whether there ARE any current entries
     */
    public function getCurrentRecords($parentName, $parentKey)
    {
        if (!empty($this->currentEntries)) {
            throw new Exception("[CODE BUG] In Matchmaker, getCurrentRecords() was called with entries still in it; did you call deleteOldRecords()?");
        }
        $this->currentEntries = [];

        $entity = $this->entityManager->_entity;
        $tableName = $this->entityManager->_schemas[$entity]['table'] ?? '';
        if ($tableName == '') {
            throw new Exception("In 'Matchmaker' getCurrentRecords(" . $entity . "), the entity has no 'table' field in the entity manager.");
        }

        $selectList = $this->getSelectList();
        $query = [];
        $query[] = "select $selectList from $tableName where cny# = :1 and $parentName = :2";
        $query[] = GetMyCompany();
        $query[] = $parentKey;
        $currentEntries = QueryResult($query, 0, 0, null, false); // no headers

        $ok = ($currentEntries !== false);
        if ($ok) {
            // normalize the raw records
            $c = 0;
            foreach ($currentEntries as $rec) {
                $this->currentEntries[] = $this->entityManager->_ProcessResult($rec); // turn things like RECORD# into RECORDNO
                $c++;
            }
            self::additionalLogging("Read $c records for $entity using a $parentName of $parentKey");
        }
        return $ok;
    }


    /**
     *      If you already HAVE the existing records in an array, you can pass them in here, thus avoiding
     *  reading the records.  This can be used in cases where the manager doesn't work the way we want....
     *
     * @param array $values     the existing records; null means 'none'
     */
    public function setCurrentRecords($values = null)
    {
        if (self::DEBUGGING && ! empty($values)) {
            $entity = $this->entityManager->_entity;
            $c = count($values);
            self::additionalLogging("Given $c records for $entity");
        }
        $this->currentEntries = $values ?? [];
    }


    /**
     *      Do an upsert on a set of records constructed in memory.
     *
     *  1) Read the existing records if parentName and parentKey are specified.  Otherwise, there would be no
     *      old records OR you could manually add records through setCurrentRecords.
     *  2) For each passed record, match it with an existing record if you can
     *     2A) if no match, add the record
     *     2B) if a match but not an exact match, update the record; mark the existing record as 'used'
     *     2C) if an exact match, don't update, but mark the existing record as 'used'
     *  3) Delete any existing records not used
     *
     * @param array     $records            the array of records you would normally pass to entity manager 'Add()' or 'Set()'
     * @param string    $parentName         The name of the parent field, like 'DOCENTRYKEY'; if empty do not look for existing records
     * @param string    $parentKey          The value of the parent field, like '123'
     *
     * @return bool                         did we upsert without error?
     */
    public function upsert(&$records, $parentName = '', $parentKey = '')
    {
        $ok = true;
        $entity = $this->entityManager->_entity;
        self::additionalLogging("Upserting entity $entity");

        // Get records if we shoud.
        // Otherwise no existing records, so everything is an ADD,
        // --or-- caller has called setCurrentRecords() with records it had
        if (($parentName != '') && ($parentKey != '')) {
            $ok = $this->getCurrentRecords($parentName, $parentKey);
        }

        // unlike EntityManager upsert, here I want to DELETE records before adding them,
        // so that, for example, docentrycost records can PUT BACK quantities before we
        // consume them again.
        $adds = [];
        $updates = [];
        foreach ($records as &$record) {
            $result = $this->matchRecord($record);
            if (($result == self::IGNORE_IDENTICAL) && ( ! $this->setEvenIfNoChange)) {
                // ignore the record
                self::additionalLogging("(Exact match, ignoring)");
            } else if ($result == self::USE_ADD) {
                $adds[] = $record;
            } else {
                $updates[] = $record;
            }
        }
        if ($ok) {
            // step one: delete the old records, potentially freeing up stuff
            $this->deleteOldRecords();

            // step two: update existing records:
            $bulk = $this->isBulkOperationEnabled($this->entityManager);
            if ($bulk) {
                if (!empty($updates)) {
                    $ok = $ok && $this->entityManager->set($updates);
                }
                if (!empty($adds)) {
                    $ok = $ok && $this->entityManager->add($adds);
                }
            } else {
                foreach ($updates as $row) {
                    $ok = $ok && $this->entityManager->set($row);
                }
                foreach ($adds as $row) {
                    $ok = $ok && $this->entityManager->add($row);
                }
            }
        }

        return $ok;
    }


    /**
     *  This simulates the Entity Manager isBulkOperationEnabled(), which is a protected method, so we can't
     *  use it directly
     *
     * @return bool
     */
    protected function isBulkOperationEnabled($entityManager)
    {
        $enableBulkOperation = $entityManager->_schemas[$entityManager->_entity]['bulkoperation'] ?? false;

        return $enableBulkOperation;
    }


    /**
     *      You want to add or set ONE record.
     *  You have already tried to add existing records from getCurrentRecords() above (or getCurrentRecordsByParent())
     *  Here, we'll see if the new record MATCHES one of the current records.
     *  If not, we'll Add().
     *  If so, and the fields have changed, we'll Set().
     *  If so, and the fields have NOT changed, we'll IGNORE
     *  We'll update the status of the existing found record, if any.
     *
     * @param array $values         the values you would normally pass to entity manager 'Add()' or 'Set()'
     *
     * @return bool
     */
    public function addOrSet(&$values)
    {
        $ok = true;
        $result = $this->matchRecord($values);
        switch ($result) {
            case self::USE_ADD:
                self::additionalLogging("Adding new record");
                $ok = $this->entityManager->add($values);
                break;

            case self::IGNORE_IDENTICAL:
                if ( ! $this->setEvenIfNoChange) {
                    // yay!  nothing to do!
                    self::additionalLogging("(Exact match, ignoring)");
                    break;
                }
                // else fall through to set

            case self::USE_SET:
                self::additionalLogging("Updating existing record " . $this->getPrimaryKeyValues($values));
                $ok = $this->entityManager->set($values);
                break;

             default:
                throw new Exception("Unkonwn switch value $result in Matchmaker::addOrSet()");
        }
        return $ok;
    }


    /**
     *      Match one exiting and one new record
     *
     * @param array     $currentEntry       An existing record
     * @param array     $newValues          A new record to be matched
     * @param bool      $exactMatch         is this an EXACT match?
     * @param array     $context            internal context to speed things up
     *
     * @return          bool                did it match?
     */
    private function matchOneRecord($currentEntry, $newValues, & $exactMatch, & $context)
    {
        $exactMatch = false;

        // shortcut: if the record# does not match, then no point in looking further
        //      Note that SOME records (like subtotalglresolve) have no record#!  (wtf?)
        //      In MANY cases, the current entry will have a record number, but the new values will NOT
        if ($this->recordNoFieldName != '') {
            $currentRecord = $currentEntry[$this->recordNoFieldName] ?? -1;   // sometimes recordno, sometimes record#
            $newRecord     = $newValues[   $this->recordNoFieldName] ?? -1;
            if (($currentRecord > 0) && ($newRecord > 0)) {
                if ($currentRecord !== $newRecord) {
                    return false;
                }
                $match = true;
                if ($this->setEvenIfNoChange) { // good enough, since we don't care about exact matches
                    return $match;
                }
            }
        }

        // if the don't BOTH have a record number, we need to do a better match.
        // we can use the 'match fields', but not if we're being conservative.....
        if (self::BE_CONSERVATIVE && ($this->matchWithMatchFields === false)) {
            // since we're called a lot if there are a lot of records, lets cache the list of fields
            if (isset($context['CompareThese'])) {
                $compareThese = $context['CompareThese'];
            } else {
                $compareThese = self::getCompareFieldsForDidExistingEntriesChange($this->entityManager, NULL);
                if ($this->recordNoFieldName != '') {
                    // we compared these above, and maybe one did not have a record#
                    unset($compareThese[$this->recordNoFieldName]);
                }
                $context['CompareThese'] = $compareThese;
            }
        } else {
            // put the match fields into the right format
            $compareThese = $context['MatchThese'] ?? [];
            if (empty($compareThese)) {
                foreach ($this->matchFields as $field) {
                    $compareThese[$field] = false;
                }
                $context['MatchThese'] = $compareThese;
            }
        }

        // Does everything in OLD ROW that appears in the SCHEMA show up in the NEW (edited) ROW?
        $match = self::detailedCompare( $compareThese, $currentEntry, $newValues, $this->nullIsThisValue );

        if (self::BE_CONSERVATIVE && ($this->matchWithMatchFields === false)) {
            $exactMatch = $match;
        }
        // we matched; do we need an exact match?
        if ($match && (! $exactMatch) && (! $this->setEvenIfNoChange)) {
            $exactMatch = $this->exactMatch($currentEntry, $newValues);
        }
        return $match;
    }


    /**
     *      Match EXACTLY one existing and one new record
     *
     * @param array     $currentEntry       An existing record
     * @param array     $newValues          A new record to be matched
     *
     * @return          bool                did it EXACTLY match?
     */
    private function exactMatch($currentEntry, $newValues)
    {
        // match forwrd
        foreach ($currentEntry as $key => $value) {
            if (!in_array($key, $this->ignoreFields)) {
                $n = $newValues[$key] ?? '';
                if ($value != $n) {
                    return false;    // not an EXACT match
                }
            }
        }
        // and backwards
        foreach ($newValues as $key => $value) {
            if (!in_array($key, $this->ignoreFields)) {
                $c = $currentEntry[$key] ?? '';
                if ($value != $c) {
                    return false;    // not an EXACT match
                }
            }
        }
        return true;    // yay! an exact match!
    }


    /**
     *      Like array_merge, but only merge the non-owned objects
     *
     * @param array $ownedList      The list of owned objects from the .ent file, if any
     * @param array $old            The existing data from sql
     * @param array $new            The new data we want to merge into it
     *
     * @return array                the merged array
     */
    static function array_merge_not_owned($ownedList, $old, $new)
    {
        // removed any owned arrays from the old/sql list
        foreach ($ownedList as $owned) {
            unset($old[$owned['path']]);
        }
        return array_merge($old, $new);
    }

    /**
     *      Does the passed record MATCH an existing record (one with a RECORD# field)?
     *  See the notes at the top of this file for how and what we match.
     *
     * @param array $newValues      the values you would normally pass to entity manager 'Add()' or 'Set()'
     *
     * @return int                  one of the constants USE_ADD / USE_SET / IGNORE_IDENTICAL
     */
    public function matchRecord(&$newValues)
    {
        $rtn = self::USE_ADD;

        // Step 1: match the MATCH FIELDS on both new and current:
        $matchesFound = [];
        $exactMatches = [];
        $context      = [];
        foreach ($this->currentEntries as $whichEntry => $currentEntry) {

            if (isset($currentEntry['DO NOT USE'])) {
                continue;   // already decided it should not be used and should be deleted.
            }

            // does it match?
            // (if the records both have record#s this will be fast)
            if ($this->matchOneRecord($currentEntry, $newValues, $exactMatch, $context)) {
                $matchesFound[] = $whichEntry;
                if ($exactMatch) {
                    $exactMatches[] = $whichEntry;
                }
            }
        }

        // Did we get some matches?  more than one? any exact?
        $numberFound = count($matchesFound);
        $exact       = count($exactMatches);
        // Take an exact match over a non-exact match
        if ($this->dupMatchesAreOk) {
            $useThisOne  = ($exact > 0)  ? $exactMatches[0] : (($numberFound > 0)  ? $matchesFound[0] : -1);
        } else {
            $useThisOne  = ($exact == 1) ? $exactMatches[0] : (($numberFound == 1) ? $matchesFound[0] : -1);
        }

        // if we didn't find a match, unset the record# in the new record, just in case it had been set
        if (($useThisOne < 0) && ($this->recordNoFieldName != '')) {
            unset($newValues[$this->recordNoFieldName]);    // in case it was set
        }

        // Now, do we have a match?  More tan one?
        if (($numberFound > 0) && ($useThisOne < 0)) {
            // found MORE THAN ONE match?  Ouch!
            // we don't want to assign any of these, because if we get it wrong, later upserts may
            // then point to the wrong record.
            self::additionalLogging("Found MORE THAN ONE MATCH for new record" . var_export($newValues,true));
            foreach ($matchesFound as $matchedRecord) {
                self::additionalLogging("Poisoning existing : " . $this->getPrimaryKeyValues($this->currentEntries[$matchedRecord]));
                $this->currentEntries[$matchedRecord]['DO NOT USE'] = true; // leave in the list for now
            }
        } else if ($useThisOne >= 0) {
            // so we DID match exactly one record....
            $currentEntry = $this->currentEntries[$useThisOne];
            self::additionalLogging("New record matched existing $useThisOne : " . $this->getPrimaryKeyValues($currentEntry));

            // Step 2: If we HAVE a match, set up the return value as Set or Ignore:
            // (i.e. do ALL non-ignore fields match both ways?)
            if ($this->setEvenIfNoChange) {
                $exactMatch = false;
            } else {
                $exactMatch = ($exact == 1);    // was there an exact match?
            }
            $rtn = $exactMatch ? self::IGNORE_IDENTICAL : self::USE_SET;  // EXACT match?

            // either way, record the record# into the new values from the existing record
            // (this is why we're here)
            $newValues[$this->recordNoFieldName] = $currentEntry[$this->recordNoFieldName];

            $foundCurrentEntry                   = $useThisOne;  // this is the key to remove when we're done.

            // Step 3: recurse down the owned-object tree, if one....
            // Are there owned objects?  If so, try to match them as well, but we don't care about add/set,
            // all we care about is the record number....
            // now recurse on owned objects:
            $fullOwnedObjectList = $this->entityManager->_schemas[$this->entityManager->_entity]['ownedobjects'] ?? [];
            foreach ($fullOwnedObjectList as $oneFullOwned) {
                if ( ! isset($this->useOwnedObjectList[$oneFullOwned['entity']])) {
                    $rtn = self::USE_SET;   // be safe, there are owned objects we don't know about.
                    break;
                }
            }
            foreach ($this->useOwnedObjectList as $owned) {
                $ownedPath    = $owned['path'];
                $newPath      = $newValues[$ownedPath] ?? [];
                $existingPath = $this->currentEntries[$foundCurrentEntry][$ownedPath] ?? [];
                // if there are no exiting records or no new records, then there's nothing to do.
                // here's a more tricky one: if there are no match fields in the .ent, then we have no way of knowing
                // HOW to match these records, so all the existing records will be deleted and the new records added,
                // which is safe, though slow.
                $e1 = empty($newPath);
                $e2 = empty($existingPath);
                $mgr = Globals::$g->gManagerFactory->getManager($owned['entity'], false, ['DOCTYPE' => $this->entityManager->_docType]);
                if ( (! $e1) && ( !$e2)) {
                    $mm = new Matchmaker($mgr, $this->setEvenIfNoChange);
                    $mm->setDupMatchesAreOk($this->dupMatchesAreOk);    // inherit this
                    $mm->setCurrentRecords($existingPath);
                    foreach ($newPath as $newKey => $dummy) {
                        $mm->matchRecord($newValues[$ownedPath][$newKey]); // curses!  He recurses!  (don't care about result)
                    }
                    $rtn = self::USE_SET;       // don't ignore the parent record if the kids exist
                }
            }

            // done with this existing entry; remove it from the list
            unset($this->currentEntries[$foundCurrentEntry]);
        }
        return $rtn;
    }


    /**
     *      Now that we're done with records, we should delete any OLD records (records we read with
     *  getCurrentRecords() or getCurrentRecordsByParent() but never matched.
     *
     * @return bool
     *
     */
    public function deleteOldRecords()
    {
        $ok = true;
        if ( ! empty($this->currentEntries)) {

            self::additionalLogging("Deleting unreferenced existing records");

            // Some entity managers are poorly behaved, like the documentEntryGLResolveManager; so this is a back door...
            // also, not ALL of these bad records even HAVE record numbers!
            if ($this->deleteByRecordNo) {
                $cny = GetMyCompany();
                $entity = $this->entityManager->_entity;
                $tableName = ($this->entityManager->_schemas[$entity]['updatetable'] ?? $this->entityManager->_schemas[$entity]['table']) ?? '';

                $qry   = [];
                $qry[] = "DELETE $tableName WHERE cny#=:1";
                $qry[] = $cny;
                $deleteTheseRecordNumbers = [];
                $useBulkDelete = false;
                foreach ($this->currentEntries as $deleteMe) {
                    $deleteRecordNumber = $deleteMe['RECORD#'] ?? ($deleteMe['RECORDNO'] ?? -1);
                    if ($deleteRecordNumber < 0) {
                        $qry2   = $qry;
                        foreach ($this->matchFields as $matchIndex => $matchField) {
                            $qry2[0] .= " and $matchField = :" . ($matchIndex + 2);
                            $qry2[] = $deleteMe[$matchField];
                        }
                        $ok = $ok && ExecStmt($qry2);   // no record number?  Abandon the batch approach, then!
                    } else {
                        $useBulkDelete = true;
                        $deleteTheseRecordNumbers[] = $deleteRecordNumber;
                    }
                }
                if ($useBulkDelete) {
                    $qry = PrepINClauseStmt($qry, $deleteTheseRecordNumbers, ' and RECORD# ');  // bulk delete.  internal record# name
                    $ok = $ok && ExecStmt($qry);
                }
            } else {
                $vidField = $this->entityManager->_schemas[$this->entityManager->_entity]['vid'] ?? $this->recordNoFieldName;
                foreach ($this->currentEntries as $deleteMe) {
                    self::additionalLogging("Deleting unreferenced existing record " . $deleteMe[$vidField] ?? '');
                    $ok = $ok && $this->entityManager->Delete($deleteMe[$vidField] ?? 0);
                }
            }
            if (!$ok && self::DEBUGGING) {
                throw new Exception("Can't delete records using vid field $vidField in Matchmaker::deleteOldRecord()");
            }
        }
        $this->currentEntries = [];
        return $ok;
    }


    /**
     *      When using didExistingEntriesChange(), below, what are the fields we should match on?
     *
     * @param EntityManager     $entityManager
     * @param EntityManager     $ownerEntityManager                 Optional 'owner' entity manager, such as DocumentManager for DocumentEntryManager
     *
     * @return string[]         the fields to match against
     */
    private static function getCompareFieldsForDidExistingEntriesChange($entityManager, $ownerEntityManager)
    {
        if (($entityManager instanceof DocumentManager) || ($entityManager instanceof DocumentEntryManager)) {
            if (!Globals::$g->islive && !isset($entityManager->_docType)) {
                throw new Exception("[Code bug] EntityManager in 'Matchmaker' compare created without DOCTYPE.");
            }
        }

        // Start with the list of 'object' fields,
        //  but filter out fields that are read-only or derived
        $compareThese       = [];
        $externalListToGet  = $entityManager->GetGetFields();
        $schema             = $entityManager->_schemas[$entityManager->_entity]['schema'];

        foreach ($externalListToGet as $externalField) {
            if (isset($schema[$externalField])) {
                $internal = $schema[$externalField];
                // don't bother with read-only child fields, like 'user.name'
                // nor with fields that are arrays (like 'DOCUMENT' => array('document.*' => 'document.*'))
                if (( ! is_array($internal)) && (strpos($internal, '.') === false)) {
                    $compareThese[$externalField] = false;  // don't allow null from the ui if it is different than disk
                }
            }
            // else, the external field may have a dot in it, like 'WAREHOUSE.LOCATION_NO'
        }

        // and lets see if there are dimension values we should NOT test if they are null....
        if ($ownerEntityManager !== null) {
            $primaryDimensions = $ownerEntityManager->getPrimaryDimensions();
            $dimFields         = $entityManager->GetDimensionFields();
            if (is_array($primaryDimensions) && is_array($dimFields)) {
                foreach ($primaryDimensions as $path => $ignore) {
                    foreach ($dimFields as $dimFieldDetails) {
                        if ($path == $dimFieldDetails['path']) {
                            $dontCompare = strtoupper($dimFieldDetails['dimfieldid']);
                            // exclude this as it must match the root
                            $compareThese[$dontCompare] = true; // allow null from the ui
                            //break;
                        } else {
                            $compareThese[$dimFieldDetails['path']] = false; // this got filtered out above because of the '.' in the schema....
                            unset($compareThese[$dimFieldDetails['dimdbkey']]);
                        }
                    }
                }
            }
        }

        // finally add in any custom dimensions...
        // lets merge custom dimension string as well
        if (IADimensions::isCustomDimensionsEnabled()) {
            $cust_dim_fields = GLEntryManager::getPTFieldsMap();
            if ($cust_dim_fields) {
                foreach ($cust_dim_fields as $field) {
                    $compareThese[$field] = false;
                }
            }
        }

        return $compareThese;
    }


    /**
     *      Did a tree of entries change? Are the entries now different than they were on disk?
     *
     * Pass an entity manager 'tree' (the object and any owned objects), and the existing tree, and we'll mark every row
     * that is different (up the chain).
     *
     * @param array         $existingEntries                    The OLD entries
     * @param array         $newEntries                         The new entries; some may exist (have record#), some may not
     * @param string[]      $recordNumberNames                  The name of the record#/id field, default is 'RECORDNO', PER ENTITY
     * @param EntityManager $ownerEntityManager                 Optional top-level 'owner' entity manager, such as DocumentManager for DocumentEntryManager
     * @param array         $customCompareByEntityName          Optional custom-compare code, use lower-case entity name as an index:
     *                                                          COMPARE_FUNCTION
     *                                                                 Optional custom function for record compares.  Use true for equal, false for not equal
     *                                                          ONLY_CUSTOM_COMPARE
     *                                                                 Set true if the custom function is enough for comparing records
     *
     * @return bool                                             true AT LEAST ONE RECORD DID CHANGE, false NONE CHANGED
     */
    public function didExistingTreeChange( &$existingEntries, &$newEntries, $recordNumberNames = [], $ownerEntityManager = null, $customCompareByEntityName = null )
    {
        $entityName    = $this->entityManager->_entity;
        $customCompare = $customCompareByEntityName[$entityName]['COMPARE_FUNCTION']    ?? null;
        $onlyCustom    = $customCompareByEntityName[$entityName]['ONLY_CUSTOM_COMPARE'] ?? false;
        $recNumName    = $recordNumberNames[$entityName] ?? 'RECORDNO';

        // Compare the base item
        self::didExistingEntriesChange($this->entityManager,$existingEntries, $newEntries,
                                $recNumName, $ownerEntityManager, $customCompare, $onlyCustom,
                                $this->nullIsThisValue);

        // there may be NO owned objects, but let's see....

        // only check the rows that we have marked as 'not changed',
        // otherwise we KNOW it changed, so no point checking further
        $unchanged = true;
        foreach ($newEntries as $index => $row) {
            if (($row['UPSERT_UNCHANGED'] ?? false) === false) {
                $unchanged = false;     // SOMETHING CHANGED!
            } else {
                // we think that, so far, things are not changed.
                // so lets recurse down the owned object path
                $ownedList = $this->entityManager->_schemas[$this->entityManager->_entity]['ownedobjects'] ?? [];
                foreach ($ownedList as $owned) {
                    $newPath        = $row[$owned['path']] ?? [];
                    $existingPath   = $row['UPSERT_EXISTING'][$owned['path']] ?? [];

                    // simple tests:
                    $newCount       = count($newPath);
                    $existingCount  = count($existingPath);
                    if ($newCount != $existingCount) {
                        unset($newEntries[$index]['UPSERT_UNCHANGED']);
                        $unchanged = false;
                        continue;
                    }

                    // another simple test:
                    if (($newCount === 0) && ($newCount === $existingCount)) {
                        continue;   // these are identical, so we keep the UPSERT_UNCHANGED
                    }

                    // The count is the same but not empty, gotta check 'em
                    // This means the customer did NOT, say, change the root record but
                    // DID change (not add, not remove, but change) one of the owned records.
                    // seems, hopefully, a low percent chance, which is why I did the outer loop
                    // as the record and the inner loop as the owned object; I think we may not get here often.
                    // but, if I'm wrong, we can flip the outer and inner loops....
                    // also note the 'useOwnedObjectList' means there's an entry in the DocumentManager::MATCHMAKER_MATCH_FIELDS
                    //  table for this entity, so we can compare.  Otherwise we cannot.
                    if (isset($this->useOwnedObjectList[$owned['entity']])) {
                        $mgr = Globals::$g->gManagerFactory->getManager($owned['entity'], false, ['DOCTYPE' => $this->entityManager->_docType]);
                        $mm = new Matchmaker($mgr, $this->setEvenIfNoChange);
                        // Curses!  He Recurses!
                        $mm->didExistingTreeChange($existingPath, $newPath, $recordNumberNames,
                            $this->entityManager, $customCompareByEntityName);
                        foreach ($newPath as $newRec) {
                            if (($newRec['UPSERT_UNCHANGED'] ?? false) === false) {
                                unset($newEntries[$index]['UPSERT_UNCHANGED']);
                                $unchanged = false;
                                break;
                            }
                        }
                    } else {
                        // have to assume they've changed!  Can't check either way!
                        unset($newEntries[$index]['UPSERT_UNCHANGED']);
                        $unchanged = false;
                    }
                }
            }
        }
        return $unchanged;
    }


    /**
     * @param string[]      $compareThese       The names of the fields to compare
     * @param string[]      $oldRow             The old record
     * @param string[]      $newRow             The new record
     * @param array         $nullIsThisValue    keyed by field, is null for a new value the same as some old value (like 'false')
     *
     * @return bool                             Do the two records match?
     */
    public static function detailedCompare( $compareThese, $oldRow, $newRow, $nullIsThisValue = [] )
    {
        $match = true;
        foreach ($compareThese as $field => $allowNull) {
            // if the fields are different and the new data is not null, then do the test
            // (if disk is not null and ui is null it is LIKELY ok, like dimension values)
            $old = ($oldRow[$field] ?? '');
            $new = ($newRow[$field] ?? '');
            // Adding new method to check if $old and $new are numeric and if they dont match.
            // self::checkForNumericValueChange($old,$new) this method is added to avoid
            // PHP 8.1 compare silent error review TM: 166719
            if (self::checkForNumericValueChange($old, $new) || $old != $new) {

                // I've seen "false" vs false, so check for them....
                if ((($old === "false") && ($new === false)) ||
                    (($old === false) && ($new === "false"))) {
                    continue;
                }
                if ((($old === "true") && ($new === true)) ||
                    (($old === true) && ($new === "true"))) {
                    continue;
                }

                if ($newRow[$field] === null) {
                    if ($allowNull) {
                        continue;
                    }
                    // sometimes the DB allows null when it really means, say, 'false'
                    if (isset($nullIsThisValue[ $field ]) && ($nullIsThisValue[ $field ] == $old)) {
                        continue;
                    }
                }

                // last gasp attempt: sometimes the ones from the UI have ID--DESC
                if (strpos($old, '--') !== false) {
                    list($old) = explode('--', $old);
                    if ($old == $new) {
                        continue;   // matches after all!
                    }
                }
                $match = false;
                break;
            }
        }
        return $match;
    }


    /**
     *      did entries change? Are the entries now different than they were on disk?
     *  This is a one-off routine to help in the case where you have on-disk (well, on-table) entries AND you
     *  have entries back from the UI, where the UI entries still have the record# from the sql table.
     *  For example, documententry records.  There can be NEW records, without record#s, of course, and some of
     *  the existing records may have changed.  Here, we 'mark' those that HAVE NOT CHANGED.
     *  We set 'UPSERT_UNCHANGED' to true.  Then, call our static method below
     *
     * @param EntityManager $entityManager                      Who is calling?
     * @param array         $existingEntries                    The OLD entries
     * @param array         $newEntries                         The new entries; some may exist (have record#), some may not
     * @param string        $rcordNumberName                    The name of the record# field, default is 'RECORDNO'
     * @param EntityManager $ownerEntityManager                 Optional 'owner' entity manager, such as DocumentManager for DocumentEntryManager
     * @param callback      $cmp_function                       Optional custom function for record compares.  Use true for equal, false for not equal
     * @param bool          $onlyCustomCompare                  Set true if the custom function is enough for comparing records
     * @param array         $nullIsThisValue                    keyed by field, is null for a new value the same as some old value (like 'false')
     *
     */
    public static function didExistingEntriesChange($entityManager, &$existingEntries, &$newEntries,
                                                    $rcordNumberName = 'RECORDNO', $ownerEntityManager = null,
                                                    $cmp_function = null, $onlyCustomCompare = false,
                                                    $nullIsThisValue = [])
    {
        $oldIndex   = [];
        foreach ($existingEntries as $key => $row) {
            $oldIndex[ $row[$rcordNumberName]] = $key;    // where is this record#?
        }

        if ( $onlyCustomCompare ) {
            $compareThese = [];
        } else {
            $compareThese = self::getCompareFieldsForDidExistingEntriesChange($entityManager, $ownerEntityManager);
        }

        // now do the compares
        foreach ($newEntries as $key => $row) {
            $recordNo = $row[$rcordNumberName] ?? 0;
            // if we can't find the record number in the existing entries,
            // then we HAVE changed.  Otherwise, let's check....
            if (isset( $oldIndex[$recordNo])) {
                $oldRow = $existingEntries[$oldIndex[$recordNo]];
                $match  = true;

                // any custom compare?
                if (($cmp_function !== null) && ($cmp_function($row, $oldRow) == false)) {
                    $match = false;
                }

                // Does everything in OLD ROW that appears in the SCHEMA show up in the NEW (edited) ROW?
                $match = $match && self::detailedCompare( $compareThese, $oldRow, $row, $nullIsThisValue );

                // do they exactly match?
                if ($match) {
                    // set both the new and the existing
                    $newEntries[$key]['UPSERT_UNCHANGED']                       = true;
                    $existingEntries[$oldIndex[$recordNo]]['UPSERT_UNCHANGED']  = true;
                    $newEntries[$key]['UPSERT_EXISTING']                        = $oldRow;  // for further tests later
                }
            }
        }
    }


    /**
     * needToUpdateLine - called before UPSERTING our child entries (like tracking detail entries)
     *      call this from the PARENT EntityManager for its Owned Objects.  Like, DocumentManager
     *      for DocumentEntry.  This is static for easy calling.  You must have called
     *      didExistingEntriesChange(), above, for this to have any value.
     *
     * @param array &$line line items
     *
     * @return bool
     */
    public static function needToUpdateLine($line)
    {
        $unchanged = $line['UPSERT_UNCHANGED'] ?? false;
        return ( ! $unchanged);     // i.e. if it DID change, then we need to update
    }



    /**
     *      If the extra logging flag is on, then put the supplied message out to the log with 'decoration' so it can
     *  be easily seen by QA/Eng
     *
     * @param string $msg       what you want added to the log
     */
    public static function additionalLogging($msg)
    {
        // Don't show the messages in production, or if we're no longer debugging
        // also note that we're not dependent on DocumentManager::$upsertFeatureInUse, but it is a good
        // way to turn off a LOT of noise....
        if (self::DEBUGGING && ! Globals::$g->islive && DocumentManager::$upsertFeaturInUse) {

            // Get the line and file of the CALLER
            $stack = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 2);
            $arr = array_shift($stack); // get the file which called this function
            $file = $arr['file'];
            $line = $arr['line'];

            LogToFile("********* $file - $line -- [Matchmaker] " . $msg);
        }
    }

    /**
     * This method is used in detailedCompare method to check old field value
     * and new field value are numeric and if they dont match return true.
     *
     * @param string/long $oldFieldValue value of field
     * @param string/long $newFieldValue value of field
     * @return bool Return true if one of the above params are numeric
     *              and if they dont match with other
     */
    private static function checkForNumericValueChange($oldFieldValue, $newFieldValue): bool
    {
        // if $oldFieldValue is numeric then $newFieldValue should also be numeric
        // if one of field value is numeric other is not return true
        if (is_numeric($oldFieldValue) != is_numeric($newFieldValue)) {
            return true;
        }
        // if $oldFieldValue, $newFieldValue are numeric and
        // both of field values dont match return true
        if ((is_numeric($oldFieldValue) && is_numeric($newFieldValue)) &&
            ((float)$oldFieldValue != (float)$newFieldValue)) {
            return true;
        }
        // if fields are numeric and matching or they fields are not numeric return false
        return false;
    }
}

