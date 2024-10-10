<?

/**
 *    FILE: InvCache.cls
 *    AUTHOR: Roger Collins
 *    DESCRIPTION:  An implementation of a 'minimal ram' table useful for large caches
 *
 *    (C) 2023, Sage / Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Sage / Intacct
 *    Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Sage / Intacct Corporation.
 */




class InvCache  implements Iterator
{
    const CHECK_SIZE         = false;               // report on bytes used by the stored data (Debugging only!)
    const CHECK_OLD_SIZE     = false;               // report on the QUERY bytes used when not using an iterator (Debugging only!)
    const USE_NO_COMPRESSION = false;               // use QueryResult() rather than QueryIterable() to see how much we save/cost

    const NameOfRowField = '__row__';           // returned records have this field to identify which row it came from

    /** @var string[] $theTable */
    private $theTable;              // the actual data, crushed down into strings

    /** @var int $theTableSize */
    private $theTableSize;          // faster than calling count() on every add

    /** @var int[] $theFields */
    private $theFields;             // fields used in the row, translated to integers (0..n) to save space

    /** @var string[] $theFieldIndexes */
    private $theFieldIndexes;       // Given an index into the above array, returns the string

    /** @var array $keys */
    private $keys;                  // keys into the data.

    /** @var array $keyNames */
    private $keyNames;              // key names in the above keys list (for speed of access)

    /** @var bool $keysUnique */
    private $keysUnique;            // is the key unique?

    /** @var int $currentKey  */
    private $currentKey;            // current row # in the iterator

    /** @var string[] $lastRead */
    private $lastRead;              // the last-read record (as a one-record cache)




    /**
     *      Constructor
     */
    function __construct()
    {
        $this->keys             = [];
        $this->keysUnique       = [];
        $this->theFields        = [];
        $this->theFieldIndexes  = [];
        $this->keyNames         = [];
        $this->reset();


        /* DEBUG TEST:
        $test = [ 'CNY#'        => 123456789012,
            'docentrykey' => 123456, 'itemkey' => 'Sledgehammer', 'whsekey' => 'NewJersey',
            'in_out' => 'O', 'quantity' => '12.443', 'qtyleft' => '1', 'docentrycostkey' => 234567, 'datein' => '01/12/2023',
            'serialno' => null, 'lotno' => null, 'binkey' => null, 'expirationdate' => '02/12/2023', 'affects_inventory' => 'T', 'cost' => 57.43, 'unitcost' => 12.78,
            'costmethod' => 'S', 'adjdocentrycostkey' => null, 'contributedqty' => 5, 'contributedcost' => 4.98,
            'isakit' => 'F'
        ];
        $howLong = 0;
        $keys = [];
        for ($i = 0; $i < 500000; $i++) {
            $start = microtime(true);
            $keys[$test['docentrykey']] = true;
            $result = igbinary_serialize($test);
            $duration = microtime(true) - $start;
            if ($duration > $howLong) {
                logFL("Test duration $duration on iteration $i");
                $howLong = $duration;
            }
            $test['CNY#']++;
            $test['docentrykey']++;
            $test['quantity']++;
            $test['docentrykey']++;
            $test['docentrycostkey']++;
            $test['cost']++;
            $test['itemkey'] = random_bytes(15);
            $test['whsekey'] = random_bytes(18);
        }
        */

    }


    //  ***************************************************************************************************
    //  ***************************************************************************************************
    //
    //  Iterator functions (so you can use foreach() )
    //
    //  ***************************************************************************************************
    //  ***************************************************************************************************


    /**
     *      How many rows are there in the table?
     *
     * @return int
     */
    public function count()
    {
        return $this->theTableSize; // count($this->theTable);
    }


    /**
     *  'rewind' to the beginning of the query return array
     */
    public function rewind()
    {
        $this->currentKey  = 0;
    }


    /**
     *      Return the current row in the data.
     *
     * @return string[]|null
     */
    public function current()
    {
        return $this->get($this->currentKey);
    }

    /**
     *      return the current key in the data; in our case the 'key' is the row number
     *
     * @return int|mixed|string|null
     */
    public function key()
    {
        return $this->currentKey;
    }


    /**
     *      increment the current key
     *
     */
    public function next()
    {
        // in a foreach loop, we will call next() prior to calling current().
        $this->currentKey++;
    }


    /**
     *      Is the current row valid?  returns TRUE or FALSE
     *
     * @return bool
     */
    public function valid()
    {
        return (($this->theTableSize > $this->currentKey) && ($this->currentKey >= 0));
    }



    //  ***************************************************************************************************
    //  ***************************************************************************************************
    //
    //  Table public functions
    //
    //  Here's how to use this class:
    //
    //  - Instantiate it
    //  - Define any keys you want (itemid, docentrycost record#, whatever)
    //      - using the name you use in the sql query (ITEMKEY, DEC, whatever)
    //  - QueryResult(), just as you would normally do, but it ONLY returns true/false
    //  THEN......
    //  - foreach (), or get(row#)
    //  - use the returned array
    //  - if you UPDATE the array, you must use put() to save it!
    //  - to do another query with the same keys, just call QueryResult() again....
    //
    //  ***************************************************************************************************
    //  ***************************************************************************************************


    /**
     *      Call this BEFORE calling QueryResult() below.
     *  This defines a KEY for the table, by name.  The name is the same name as used in the sql query.
     *  So, for example, if your sql says something like 'select record# as recno, ....' you could say
     *  here defineKey('RECNO');
     *
     *      After querying, you can then fetch one or more records by this key.  The key need not be
     *  unique.  Call getRowsByKeyValue() and it returns an array of row numbers, then call get(row).
     * Or call getByKey().
     *
     * @param string $keyName
     */
    public function defineKey($keyName, $unique = true)
    {
        if (!empty($this->theTable)) {
            throw new Exception("[Code Bug] Call defineKey BEFORE QuerySelect");
        }
        $this->keys[$keyName] = [];
        $this->keysUnique[$keyName] = $unique;
        $this->keyNames = array_keys($this->keys);  // for faster access when adding to them
    }


    /**
     * This functionally mimics a QueryResult() call, with the SAME first parameter.
     *
     *  However, it returns TRUE or FALSE
     *
     * The callback is called once for each record read, prior to adding it to the table.
     *
     * @param array|string $stmt_desc
     * @param callable     $callback            optional.  Passed the row before saving it, saves the returned row
     * @param array|null   $callbackContext     optional.  Context to be passed to the callback
     *
     * @return bool
     *
     */
    public function QueryResult($stmt_desc, $callback = null, $callbackContext = null)
    {
        $reportMemory = function($used, $rows) {
            $used           = memory_get_usage() - $used;
            $columns        = self::USE_NO_COMPRESSION ? count($this->theTable[0] ?? []) : count($this->theFields);
            $bytesPerRow    = $rows ? round($used / $rows, 2) : 0;
            $used           = number_format($used);
            $bytesPerRow    = number_format($bytesPerRow,2);
            $query          = self::USE_NO_COMPRESSION ? 'QueryResult()' : 'QueryIterable()';
            logFL( "Memory used by $query : $used for $rows rows, $columns columns.  Bytes per row: $bytesPerRow ");
        };

        //  *************************************
        //  INITIALIZE
        //  *************************************
        $this->reset();

        $used = 0;          // so inspections don't bitch at me
        if (self::CHECK_SIZE && (! Globals::$g->islive)) {
            $used = memory_get_usage(); // in case we're measuring
        }

        //  *************************************
        //  DO QUERY, GET AN ITERATOR
        //  *************************************
        $result = self::USE_NO_COMPRESSION ? QueryResult($stmt_desc) : QueryIterable($stmt_desc);
        if ($result === false) {
            return false;       // something wrong, likely with your query.  Check the log file!
        }
        // $result is a ResultSetIterator or an array, depending...

        //  *************************************
        //  GET ROWS
        //  *************************************
        foreach ($result as $row) {
            if ($callback) {
                $row = $callback($row, $callbackContext);
                if ($row === null) {    // callback rejected this row
                    continue;
                }
            }
            $this->add($row);
        }

        if ( ! self::USE_NO_COMPRESSION) {
            $result->close();   // close the iterator
        }
        unset($result);

        if (self::CHECK_SIZE && (! Globals::$g->islive)) {
            $reportMemory($used, $this->count());
        }

        return true;
    }



    /**
     *  get one row
     *
     * @param int $rowNumber
     *
     * @return array|null
     */
    public function get($rowNumber)
    {
        $row = null;
        // a tiny bit faster if the row was just read....
        if ($rowNumber === ($this->lastRead[self::NameOfRowField] ?? -1)) {
            return $this->lastRead;
        }
        if (($this->theTableSize > $rowNumber) && ($rowNumber >= 0)) {
            if (self::USE_NO_COMPRESSION) {
                $row = $this->theTable[$rowNumber];
            } else {
                $row = $this->myUnserialize($this->theTable[$rowNumber]);
            }
            $row[self::NameOfRowField] = $rowNumber;
            $this->lastRead            = $row;
        }
        return $row;
    }


    /**
     *  get one row by key field, or a bunch of rows.  If the key has multiples, this returns them all.
     * YOU NEED TO KNOW IF THIS RETURNS ONE OR MANY.
     *
     * @param string $key
     * @param string $field
     *
     * @return array|null
     */
    public function getByKey($key,$field)
    {
        $rowNumbers = $this->getRowsByKeyValue($key, $field);
        if (is_int($rowNumbers)) {
            return $this->get($rowNumbers);
        }
        $rtn = [];
        foreach ($rowNumbers as $rowNumber) {
            $rtn[] = $this->get($rowNumber);
        }
        return $rtn;
    }


    /**
     *  put one row back; don't bother to do this if you have not changed it.
     *  Also, you CANNOT CHANGE the key values!
     *
     *
     * @param string[]  $row
     *
     */
    public function set($row)
    {
        $rowNumber = $row[self::NameOfRowField] ?? -1;
        if ($rowNumber < 0) {
            throw new Exception("[Code Bug] Bad data passed to 'InvCache::set'");
        }
        // re-encode it
        $this->theTable[$rowNumber] = (self::USE_NO_COMPRESSION) ? $row : $this->mySerialize($row);
        $this->lastRead             = []; // invalidate the one-record cache
    }


    /**
     *  remove all data from the table, keep the key definitions
     */
    public function reset()
    {
        $this->currentKey = 0;
        $this->theTable   = [];
        $this->lastRead   = [];
        $this->theTableSize = 0;
        foreach ($this->keys as $key => $values) {
            $this->keys[$key] = [];
        }
    }


    /**
     *  get a set of row numbers by key name and key value.
     *
     *  - The returned row numbers can be given to get().
     *  - The keyName should be the same as the call to defineKey(), above
     *  - if $keyValue is matched and the corresponding rows are returned
     *  - The key need not be unique, so the return can be a set of values
     *      - based on the 'unique' setting when adding a key
     *
     * @param string      $keyName
     * @param string      $keyValue
     *
     * @return int|int[]     might be empty
     */
    public function getRowsByKeyValue($keyName, $keyValue)
    {
        if (!isset( $this->keys[$keyName])) {
            throw new Exception("[Code Bug] key $keyName not defined");
        }
        if ($this->keysUnique[$keyName]) {
            return $this->keys[$keyName][$keyValue] ?? -1;
        }
        return $this->keys[$keyName][$keyValue] ?? [];
    }


    /**
     *      Get the array of key values for a key.  For example, you want to know
     *   all the record#s you got so you can use them in another query...
     *
     * @param string $keyName
     *
     * @return string[]
     */
    public function getRowKeys($keyName)
    {
        if (!isset( $this->keys[$keyName])) {
            throw new Exception("[Code Bug] key $keyName not defined");
        }
        return array_keys($this->keys[$keyName]);   // might be empty
    }


    /**
     * @param array $row
     */
    public function add($row)
    {
        // collect any key values
        foreach ($this->keyNames as $key) {
            $thisValue = $row[$key] ?? NULL;
            if (($thisValue !== NULL) && ($thisValue !== '')) {
                if ($this->keysUnique[$key]) {
                    $this->keys[$key][$thisValue] = $this->theTableSize;
                } else {
                    $this->keys[$key][$thisValue][] = $this->theTableSize;
                }
            }
        }

        if (self::USE_NO_COMPRESSION) {
            $this->theTable[] = $row;
        } else {
            $this->theTable[] = $this->mySerialize($row);
        }
        $this->theTableSize++;
        $this->lastRead   = []; // invalidate the one-record cache
    }


    /**
     *      Use igbinary_serialize to serialize the row, but ALSO take out the keys and make a keyless row
     *  in order to save space.  e.g., if 10,000 records have 'RECORD#' in them, now they'll just have an int like 2.
     *
     * @param string[] $row
     *
     * @return string|false
     */
    private function mySerialize($row)
    {
        $keys = [];
        foreach ($row as $key => $value) {
            // we extend the list of keys if need be, and we don't need to do
            // this on de-serialize, so that runs a tad faster.  Hopefully
            // we read as much or more than we write....
            // Also, we likely don't extend the list often, so only the first time
            // are we calling count() (a few times)
            $fieldIndex = $this->theFields[$key] ?? -1;
            if ($fieldIndex < 0) {
                $fieldIndex              = count($this->theFields);
                $this->theFields[$key]   = $fieldIndex;             // i.e. the first entry is 0, second is 1, ...
                $this->theFieldIndexes[$fieldIndex] = $key;         // i.e. entry 0 is the first key, 1 is the second,...
            }
            $keys[] = $fieldIndex;
        }
        return igbinary_serialize(array_combine($keys, $row)); // replace the original keys with the numeric indexes
    }


    /**
     * @param string|bool|null $shavedRow
     *
     * @return string[]
     */
    private function myUnserialize($shavedRow)
    {
        if (($shavedRow === null) || ($shavedRow === false)) {
            return [];
        }

        $newKeys = [];
        $row     = igbinary_unserialize($shavedRow);
        $keys    = array_keys($row);
        foreach ($keys as $key) {
            $newKeys[] = $this->theFieldIndexes[$key];  // here '$key' is the numeric index for the field name
        }
        return array_combine($newKeys, $row);
    }
}

