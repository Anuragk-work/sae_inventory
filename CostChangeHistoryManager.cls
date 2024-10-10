<?php
/**
 * Created by PhpStorm.
 * User: rcollins
 * Date: 2/19/2019
 * Time: 2:04 PM
 */

class CostChangeHistoryManager extends OwnedObjectManager
{
    // see costchangehistory.cqry queries
    const  MAXIMIM_RETURNED_DETAILS         = 500;
    const  MAXIMUM_RETURNED_SUMMARIES       = 200;


    /** @var bool $returnSummariesOnly   Should the parent query return summaries or details? */
    public $returnSummariesOnly = false;


    /**
     * Constructor
     *
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
    }


    /**
     *      Lookup login name from the record#.  Faster than doing it in the owned objct...
     *  (because of a small cache)
     *
     *  Note: MOST MIV runs are run by the Admin or Intacct user, or one of a few warehouse users.
     *
     * @param int   $id     the login record number
     *
     * @return string
     */
    private function getLoginFor($id)
    {
        static $cache = [];

        if ( ! isset($cache[$id])) {
            $query = [];
            $query[0] = "SELECT loginid from userinfomst where cny#=:1 AND record#=:2";
            $query[1] = GetMyCompany();
            $query[2] = $id;
            $result = QueryResult($query);
            if (($result !== false) && isset($result[0])) { // did we get a record back?
                $cache[$id] = $result[0]['LOGINID'];
            } else {
                $cache[$id] = '?? ' . $id;                  // unknown?
            }
        }
        return $cache[$id];
    }



    /**
     * _ProcessResult method
     *
     *      This is called after a get() of any flavor, even API_Get().
     *  AND it is called after a query for Owned Objects.  If not here, it is hard to find
     *  a single choke point to use to play with the results of queries.
     *
     *  Here all I'm doing is a simple login id lookup.  Yes, there are mechanisms in the .ent file for it,
     *  but when reading a thousand records with two lookups per it does add up!
     *
     * @param array|bool $result all the values
     * @param array $fields all the fields
     *
     * @return array $result processed result
     */
    function _ProcessResult($result, $fields=null)
    {
        $result = parent::_ProcessResult($result, $fields);

        // Doing these here is much faster than doing them, often in a loop, for the whole set.
        $result['TXNCREATEDBYID']  = $this->getLoginFor( $result['TXNCREATEDBY']  ?? 0 );
        $result['TXNMODIFIEDBYID'] = $this->getLoginFor( $result['TXNMODIFIEDBY'] ?? 0 );

        // The default read of records with type timestamp can yield something like:
        // '23-MAY-19 09.48.55.000000 PM', which is in GMT.  What the JS routines want
        // is a date format of '/mdY' and a time format of 'HH24:MI:SS'.
        // Not sure how we're going to deal with international formatting, but for now
        // I will convert the format Oracle gives me to the expected JS format.
        // I could also write a custom query in a CQRY file, but that would also involve
        // maintenance.
        $gmt = new DateTimeZone("GMT");
        $t   = DateTime::createFromFormat('j-M-y h.i.s.u A', $result['COSTINGUPDATEDON'], $gmt);
        if ($t !== false) {
            $result['COSTINGUPDATEDON'] = $t->format('m/d/Y H:i:s');
        }

        $t   = DateTime::createFromFormat('j-M-y h.i.s.u A', $result['PRIORCOSTINGUPDATEDON'], $gmt);
        if ($t !== false) {
            $result['PRIORCOSTINGUPDATEDON'] = $t->format('m/d/Y H:i:s');
        }

        return $result;
    }


    /**
     *  Replace the standard SELECT_BY_PARENT query with our own that is sorted correctly.
     *    .. and, if desired, returns ONLY summary records.
     *
     *
     * @return string
     */
    function GetQueryName()
    {
        return $this->returnSummariesOnly ? 'QRY_COSTCHANGEHISTORY_SELECT_BY_PARENT_ORDERED_SUMMARIES' : 'QRY_COSTCHANGEHISTORY_SELECT_BY_PARENT_ORDERED';
    }


    /**
     * @param string $startDate         a date for the beginning of the range of MIV runs
     * @param string $endDate           a date for the end of the range of MIV runs
     *
     * @return string[][]|bool
     */
    public function getFromCostingDateRange($startDate, $endDate)
    {
        // Get the user's dates, and default them as needed
        $startTimestamp = GetGMTTimestampFromTimestamp( GetTimestampFromDate($startDate));
        $endTimestamp   = GetGMTTimestampFromTimestamp( GetTimestampFromDate($endDate));

        $query = [];
        $query[] = "SELECT * FROM costchangehistory WHERE cny#=:1 
                    AND costingupdatedon>=TO_TIMESTAMP(:2, 'MM/DD/YY HH24:MI:SS') AND costingupdatedon<=TO_TIMESTAMP(:3, 'MM/DD/YY HH24:MI:SS') 
                    AND isasummary='T'
                    ORDER BY transactioneffectivedate, itemid, warehouseid, incrementordecrement desc, transactionname, transactionid, isasummary desc";
        $query[] = GetMyCompany();
        $query[] = $startTimestamp;
        $query[] = $endTimestamp;

        return QueryResult($query);
    }



}

