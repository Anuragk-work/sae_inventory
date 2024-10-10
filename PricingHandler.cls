<?

/**
 *    FILE: PricingHandler.cls
 *    AUTHOR: Sudeendra Rao
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 *  Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */


define('DEFAULT_INVPRECISION', 2);

require_once 'util.inc';


/**
 * Class PricingHandler
 */
class PricingHandler
{
    const       CACHED_QUERY_MAXIMUM    = 300;  // allow no more than this many different queries of any one query string



    /**
     *  Should we use a cache for queries in here?
     *      Note: the question arises, "why not ALWAYS use the cache?" and the answer is: testing.
     *          We'll test the cases we know about when we turn on the cache, but it is hard to know
     *          if we've tested every path, so we leave the old, tested, code in place.
     *
     * @var bool $cacheQueries
     */
    private     $cacheQueries   = false;    // saves time when doing bulk pricing, as Replenishment and other generators would

    /**
     * @var     array        $queryCache
     *
     *      The first level key is the query string
     *      The second level key is the serialized parameters to the query (not including the query itself)
     *
     *      The PAYLOAD of the cache is [ query result, matches ], where matches is the number of times this cache item was used.
     *      To trim the cache when it gets to CACHED_QUERY_MAXIMUM, we go through the list pruning entries used less than n% of the time,
     *          or the smallest amount used.  Ya, this is clunky, but means that we don't need a fancy secondary queue or something to
     *          manage the least-used (like a linked-list).  Let's see how slow this gets....
     */
    private     $queryCache     = [];

    /**
     *      For the above cache, this array has a primary key of the sql query string, and contains the COUNT of
     *   instances in the queryCache for that sql query.  This is because I'm told count() is slow....
     *
     * @var int[] $queryCacheCount
     */
    private     $queryCacheCount     = [];

    /**
     *      If the cache is on, we cache ancestor queries in here; this is different than the above cache because
     *  this is the result of a
     *
     * @var array $ancestorCache
     */
    private     $ancestorCache    = [];

    /**
     * @var null|bool[][] $cachedPriceListItems     for each item, what price lists does it have?
     */
    private     $cachedPriceListItems = null;

    /**
     * @var null|bool[][] $cachedPriceListProductLines     for each product line, what price lists does it have?
     */
    private     $cachedPriceListProductLines = null;

    /**
     *  is Sales Force installed?  (only used when cacheing is on)
     *
     * @var null|bool   $salesForceInstalled
     */
    private     $salesForceInstalled = NULL;

    /**
     *  what are the Sales Force Prefs?  (only used when cacheing is on)
     *
     * @var null|array   $salesForcePrefs
     */
    private     $salesForcePrefs = NULL;


    /**
     * PricingHandler constructor.
     *
     */
    function __construct()
    {
        // Do not implement anything in this constructor, this is suppose to be stateless class
        return true;  // TODO: Constructors should not have return values
    }


    /**
     *  For bulk pricing, cacheing queries can speed things up a fair amount.
     *  Things like PO generators (like Replenishment) that look up pricing can benefit a fair amount.
     *
     * @param bool $on
     */
    public function CacheQueries($on = true)
    {
        $this->cacheQueries = $on;
        if (!$on) {
            $this->flushCache();
        }
    }


    /**
     *      The cache for the passed query is 'full', meaning it has more than CACHED_QUERY_MAXIMUM results.
     *  Here, we reduce by some number (1 to all) using an algorithm that, hopefully, in most cases,
     *  runs in good time.
     *
     * @param string    $query      the sql qurey with too-many results
     *
     */
    private function ReduceCache($query)
    {
        $count = $this->queryCacheCount[$query];    // probably CACHED_QUERY_MAXIMUM....
        if ($count < self::CACHED_QUERY_MAXIMUM) {
            return; // why did you call?
        }
        // Remove anything performaing at less than 5% of hits
        // or performing less than the min we saw last time
        $removeIfLessThan = ($count / 20.0);  // so, like, 500 => 25  or 300 => 15
        $removeIfLessThan = ($removeIfLessThan > 3) ? $removeIfLessThan : 3;                // nothing like heuristics!

        $leastMatch = PHP_INT_MAX;
        $leastKey   = 0;
        $foundOne = false;
        foreach ($this->queryCache[$query] as $key => $queryInstance) {
            $matches = $queryInstance['MATCHES'];
            if ($matches < $removeIfLessThan) {
                unset($this->queryCache[$query][$key]);
                $count--;
                $foundOne = true;
            } else if ($matches < $leastMatch) {    // more than our threshold, but less than others?
                $leastMatch = $matches;
                $leastKey   = $key;
            }
        }

        // If our 'threshold search' yielded no results, remove the one entry with the least matches.
        // worst case, we do this for every add!  Eeeek!
        if ($foundOne == false) {
            unset($this->queryCache[$query][$leastKey]);     // remove the key with the least matches
            $count--;
        }
        $this->queryCacheCount[$query] = $count;
    }


    /**
     *  Add one result to the cache of results. May make room if needed
     *
     * @param string            $query                  the sql query
     * @param string            $serializedParameters   serialized query parameters
     * @param bool|string[]     $queryResult            could be empty or false
     *
     * assert: cache is on
     */
    private function AddToCache($query, $serializedParameters, &$queryResult)
    {
        if (isset($this->queryCacheCount[$query])) {
            if ($this->queryCacheCount[$query] >= self::CACHED_QUERY_MAXIMUM) {
                $this->ReduceCache($query);
            }
        } else {
            $this->queryCacheCount[$query] = 0; // first entry for this query
        }
        $this->queryCacheCount[$query]++; // faster than count(), I think
        $this->queryCache[$query][$serializedParameters] = ['RESULT' => $queryResult, 'MATCHES' => 1]; // yes, even cache 'false' or count=0
    }


    /**
     *      If you change data that could invalidate cached queries, flush the cache.  Better safe than sorry!
     */
    protected function flushCache()
    {
        $this->queryCache                   = [];
        $this->queryCacheCount              = [];
        $this->ancestorCache                = [];
        $this->cachedPriceListItems         = [];
        $this->cachedPriceListProductLines  = [];
    }


    /**
     *  General Purpose sql query that can cache the results when cacheing is on.
     *  If the cache is NOT on, then we just do the query.
     *  If the cache IS on, then we cache the query, using the parameter array as the cache key.
     *  Note: with lots of queries there may be a TON of different queries (e.g. one per item),
     *      so we want to make sure the cache doesn't get TOO large.
     *
     * @param array $queryArray
     *
     * @return bool|string[][]
     */
    protected function DoOneQuery($queryArray)
    {
        if ($this->cacheQueries) {
            $query = $queryArray[0];
            $smallerArray = $queryArray;
            $smallerArray[0] = ''; // seems faster than unset(), which has to move everything up
            $serializedParameters = serialize($smallerArray);
            if (isset( $this->queryCache[$query][$serializedParameters])) {
                $this->queryCache[$query][$serializedParameters]['MATCHES']++;  // scored another hit on this entry
                return $this->queryCache[$query][$serializedParameters]['RESULT'];
            }
        }
        $result = QueryResult($queryArray);
        if (isset($query, $serializedParameters) && $this->cacheQueries) { // query and $serializedParameters are defined, but the inspection process doesn't know it....
            $this->AddToCache($query,$serializedParameters,$result);    // yes, cache 'false' returns and empty returns...
        }
        return $result;
    }


    /**
     * This function would prepare the initial parameters need to be feeded to the SuggestPrice.
     * This is to avoid repetite items done in the SuggestPrice, since the SuggestPrice is mostly called from for loop.
     *
     * @param string    $_contactid
     * @param string    $_billto
     * @param string    $_shipto
     * @param string    $_time
     * @param string    $_mod
     *
     * @return array
     */
    function PrepParams($_contactid, $_billto, $_shipto, $_time, $_mod)
    {
        global $gManagerFactory;

        $enttype    = $_mod == 'so' ? 'customer' : 'vendor';
        $mgr        = $gManagerFactory->getManager($enttype);

        $fields     = array('PRCLST_OVERRIDE','OEPRCLSTKEY','OEPRICESCHEDKEY','DISCOUNT');
        //$_contact	= $mgr->Get($_contactid);

        if ($enttype == 'customer') {
            if($_contactid != '') {
                $_contact     = $mgr->GetList(
                    array('selects' => $fields,
                    'filters' => array(array(
                      array('CUSTOMERID', '=' , $_contactid)))
                    )
                );
                $_contact     = $_contact[0];
            }
        }else{
            if($_contactid != '') {
                // $_contact    = $mgr->get($_contactid);   // gets a LOT, takes a bunch of time....
                $stmt       = [];
                // note: there is no PRCLST_OVERRIDE in vendors
                $stmt[]     = "SELECT OEPRCLSTKEY, OEPRICESCHEDKEY, DISCOUNT FROM vendormst WHERE vendorid =:1  AND cny# =:2";
                $stmt[]     = $_contactid;
                $stmt[]     = GetMyCompany();
                $_contact   = $this->DoOneQuery($stmt);
                if (($_contact === false) || (count($_contact) == 0)) {
                    $_contact = null;
                } else {
                    $_contact = $_contact[0];
                }
            }
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $priceListOverride    = $_contact['PRCLST_OVERRIDE'];

        /** @var DocumentSetupManager $setupMgr */
        $setupMgr    = $gManagerFactory->getManager($_mod . 'setup');
        $modPrefs    = $setupMgr->get('');

        $contactMgr            = $gManagerFactory->getManager('contact');
        $contactversionMgr    = $gManagerFactory->getManager('contactversion');

        $vrec = '';
        // Check Billing/Shipping contact
        if ($priceListOverride == 'B' && isset($_billto)) {
            $vrec = $contactMgr->GetCurrentVersionNo($_billto);
        } elseif($priceListOverride == 'S' && isset($_shipto)) {
            $vrec = $contactMgr->GetCurrentVersionNo($_shipto);
        }

        $billshipContact = array();
        if ($vrec != '') {
            // get the billing/shipping contact's price list/ price schedule/ discount
            $billshipContact    = $contactversionMgr->get($vrec);
        }

        /**
 * This is for FetchPrice API
**/
        $ismcpEnabled = IsMCPEnabled($_mod);
        $basecurrency = GetBaseCurrency();
        /**
 * This is for FetchPrice API
**/
        // To speed up searches of the price lists, lets see if a given item or product line HAS a given price list
        //  that is active today.
        //  This way, we know if it is possible to get details or not; often it is not.
        //  This saves us the exhaustive searches we would otherwise do for every item/product for every price list.
        // What we DON'T know here is if there are quantity discounts or multi-currency discounts, but this is a good start.
        if ($this->cacheQueries && (($this->cachedPriceListItems == null) || ($this->cachedPriceListProductLines == null))) {
            $stmt = [];
            $this->cachedPriceListItems = [];
            $this->cachedPriceListProductLines = [];
            // I basically want one row per the three fields listed; otherwise there'll be lots of dups
            $stmt[] = "     SELECT  prclstkey, productlinekey, itemkey, count(*)
                            FROM oeprclstitems 
                            WHERE
                               (cny# = :1) and
                               (qtyval='Q') and
                               (datefrom <= :2 or datefrom is null) and
                               (dateto >= :2 or dateto is null)
                            GROUP BY  prclstkey, productlinekey, itemkey";
            $stmt[] = GetMyCompany();
            $stmt[] = $_time;
            $priceListItems = $this->DoOneQuery($stmt);
            if (($priceListItems !== false) && ((!empty($priceListItems)))) {
                foreach ($priceListItems as $priceListItem) {
                    $this->cachedPriceListItems[$priceListItem['ITEMKEY']][$priceListItem['PRCLSTKEY']] = true;    // yes, it is worth searching for
                    if ($priceListItem['PRODUCTLINEKEY'] != '') {
                        $this->cachedPriceListProductLines[$priceListItem['PRODUCTLINEKEY']][$priceListItem['PRCLSTKEY']] = true;    // yes, it is worth searching for
                    }
                }
            }
        }

        $priceScheduleEntity = $this->getPriceScheduleEntity($_mod);

        $params = array(
            'MOD'        =>    $_mod,
            'ENTITY'     =>    $enttype,
            'CONTACT'    =>  array (
                                        'PRCLST_OVERRIDE' =>    $_contact['PRCLST_OVERRIDE'],
                                        'OEPRCLSTKEY'     =>    $_contact['OEPRCLSTKEY'],
                                        'OEPRICESCHEDKEY' =>    $_contact['OEPRICESCHEDKEY'],
                                        'DISCOUNT'        =>    $_contact['DISCOUNT'],
                                    ),
            'MODPREF_PRICING'    => $modPrefs['PRICING'],
            'FORMATTTED_TIME'    => $_time,
            'BILLSHIPCONTACT'    => $billshipContact,
            'ISMCPENABLED'       => $ismcpEnabled,
            'BASECURRENCY'       => $basecurrency,
            'INVPRICELISTMGR'    => Globals::$g->gManagerFactory->getManager('invpricelist'),
            'PRICESCHEDMGR'      => Globals::$g->gManagerFactory->getManager($priceScheduleEntity),
        );

        return $params;
    }


    /**
     * Before calling SuggestPrice, call the PrepParams outside any forloop and pass the params value from PrepParams into this function.
     *
     * @param array     $priceParams
     * @param string    $_productid
     * @param string    $_prodline
     * @param float     $_quantity
     * @param array     $_document
     * @param string    $_currency
     * @param null|bool $priceMissing
     *
     * @return float
     */
    function SuggestPrice(&$priceParams, $_productid, $_prodline, $_quantity, $_document, $_currency='', &$priceMissing=null)
    {
        $plManager        =  $priceParams['INVPRICELISTMGR'];
        if (!$plManager) {
            $plManager = Globals::$g->gManagerFactory->getManager('invpricelist');
        }
        $schedManager     =  $priceParams['PRICESCHEDMGR'];
        if (!$schedManager) {
            $priceScheduleEntity = $this->getPriceScheduleEntity($priceParams['MOD']);
            $schedManager = Globals::$g->gManagerFactory->getManager($priceScheduleEntity);
        }

        $degree = 10;
        $price    = '';

        // Check base price list
        $pricelist = $_document['PRCLISTKEY'];
        $PriceRec = $this->FetchPrice($pricelist, $_productid, $_prodline, $_quantity, $priceParams, $_currency);
        $PriceRec =  $PriceRec[0] ?? [];

        if ((!empty($PriceRec))) {
            $priceParams['PRICELISTS'][$pricelist]['HASENTRY'] = true;
            if ($PriceRec['VALUETYPE']=='ACTUAL') {
                $price=$PriceRec['VALUE'];
            }
            if ($PriceRec['FIXED']=='Y') {
                return $price;
            }
        }else{
            $priceParams['PRICELISTS'][$pricelist]['HASENTRY'] = false;
        }

        // Check special price list
        if ($_document['SPCLPRCLISTKEY'] !='') {
            $pricelist = $_document['SPCLPRCLISTKEY'];
            $PriceRec = $this->FetchPrice($pricelist, $_productid, $_prodline, $_quantity, $priceParams, $_currency);
            $PriceRec =  $PriceRec[0] ?? [];
            if ((!empty($PriceRec))) {
                $priceParams['PRICELISTS'][$pricelist]['HASENTRY'] = true;
                $price=$this->CalcPrice($PriceRec, $price);
                if ($PriceRec['FIXED']=='Y') {
                    return $price;
                }
            }else{
                $priceParams['PRICELISTS'][$pricelist]['HASENTRY'] = false;
            }
        }

        $_contact = $priceParams['CONTACT'];

        // Check customer/vendor
        if($priceParams['ENTITY'] == 'customer') {
            $priceListOverride = $_contact['PRCLST_OVERRIDE'];

            // check customer price list/ price schedule/ discount
            if ($priceListOverride == 'C') {
                $pricelist            = $_contact['OEPRCLSTKEY'];
                $_pricescheduleid    = $_contact['OEPRICESCHEDKEY'];
                $discount            = $_contact['DISCOUNT'];

            } else {

                $billshipContact    = $priceParams['BILLSHIPCONTACT'];
                $pricelist            = $billshipContact['PRICELISTKEY'];
                $_pricescheduleid    = $billshipContact['PRICESCHEDULE'];
                $discount            = $billshipContact['DISCOUNT'];

                // check the contact pricelist is valid
                $rec = $plManager->get($billshipContact['PRICELIST']);
                if ($rec['SALEPURCHASE'] != 'Sales') {
                    $pricelist = '';
                }

                // check the contact priceschedule is valid
                $prcshed = $schedManager->get($_pricescheduleid);
                if($prcshed['SCHEDTYPE'] != 'Sales') {
                    $_pricescheduleid ='';
                }
            }

            // check for vendor price list/ price schedule / discount
        } else {
            $pricelist            = $_contact['OEPRCLSTKEY'];
            $_pricescheduleid    = $_contact['OEPRICESCHEDKEY'];
            $discount            = $_contact['DISCOUNT'];
        }

        // Check customer/contact/vendor price list
        if ($pricelist !='' && $priceParams['MODPREF_PRICING']['USEPRICELISTS'] == 'true') {
            $PriceRec = $this->FetchPrice($pricelist, $_productid, $_prodline, $_quantity, $priceParams, $_currency);
            $PriceRec =  $PriceRec[0] ?? [];
            if ((!empty($PriceRec))) {
                $priceParams['PRICELISTS'][$pricelist]['HASENTRY'] = true;
                $price=$this->CalcPrice($PriceRec, $price);
                if ($PriceRec['FIXED']=='Y') {
                    return $price;
                }
            }else{
                $priceParams['PRICELISTS'][$pricelist]['HASENTRY'] = false;
            }
        }

        // Check customer/contact/vendor schedule price list
        if ($_pricescheduleid !='' && $priceParams['MODPREF_PRICING']['USEPRICESCHED'] == 'true') {
            $priceschedule = $schedManager->GetRaw($_pricescheduleid);
            $priceschedule = $priceschedule[0];
            if ($priceschedule['PRICELISTKEY'] !='') {
                $pricelist = $priceschedule['PRICELISTKEY'];
                $PriceRec = $this->FetchPrice($pricelist, $_productid, $_prodline, $_quantity, $priceParams, $_currency);
                $PriceRec =  $PriceRec[0] ?? [];
                if ((!empty($PriceRec))) {
                    $priceParams['PRICELISTS'][$pricelist]['HASENTRY'] = true;
                    $price=$this->CalcPrice($PriceRec, $price);
                    if ($PriceRec['FIXED']=='Y') {
                        return $price;
                    }
                }else{
                    $priceParams['PRICELISTS'][$pricelist]['HASENTRY'] = false;
                }
            } else {
                if ($price != '' && $priceschedule['DISC'] !='') {
                    $price=ibcsub($price, ibcdiv(ibcmul($price, $priceschedule['DISC'], $degree, true), '100', $degree, true), $degree, true);
                }
            }
        }
        // Check customer/contact/vendor discount
        if ($price != '' && $discount !='' && $priceParams['MODPREF_PRICING']['USEDISCOUNT'] == 'true') {
            $price=ibcsub($price, ibcdiv(ibcmul($price, $discount, $degree, true), '100', $degree, true), $degree, true);
            return $price;
        }

        // if price still not found, check if we should fall back on the Base Price List
        if ($price == '' && isset($priceParams['BASEPRICELISTKEY'])) {
            $PriceRec = $this->FetchPrice($priceParams['BASEPRICELISTKEY'], $_productid, $_prodline, $_quantity, $priceParams, $_currency);
            $PriceRec =  $PriceRec[0] ?? [];
            if ((!empty($PriceRec))) {
                $price = $this->CalcPrice($PriceRec, $price);
            }
        }

        // check if caller wishes to distinguish between a missing price and an actual price of zero
        if ($priceMissing !== NULL) {
            $priceMissing = $price === '';
        }

        if ($price == '') {
            $price = 0;
        }

        return $price;
    }

    /**
     * @param string $mod
     *
     * @return string
     */
    public function getPriceScheduleEntity($mod)
    {
        $priceScheduleMgr = 'priceschedule';
        switch (strtolower($mod)) {
            case 'so':
                $priceScheduleMgr = 'sopriceschedule';
                break;

            case 'po':
                $priceScheduleMgr = 'popriceschedule';
                break;
        }

        return $priceScheduleMgr;
    }


    /**
     * Some Description
     * this is used to check if the price list exist in any of the pricelists configured
     * used when generating renewals
     *
     * @param array $priceParams
     *
     * @return bool
     */
    function hasPriceListEntry($priceParams)
    {
        foreach($priceParams['PRICELISTS'] as $priceList){
            if($priceList['HASENTRY']) {
                return true;
            }
        }
        return false;
    }


    /**
     * @param array $prcrec
     * @param float $curprice
     *
     * @return float
     */
    function CalcPrice($prcrec, $curprice)
    {
        $degree = 10;
        $price=$curprice;
        if ($prcrec['VALUETYPE']=='ACTUAL') {
                $price=$prcrec['VALUE'];
        }
        elseif ($prcrec['VALUETYPE']=='DLR_MARKUP') {
                $price=ibcadd($curprice, $prcrec['VALUE'], 10, true);
        }
        elseif ($prcrec['VALUETYPE']=='DLR_DISC') {
                $price=ibcsub($curprice, $prcrec['VALUE'], 10, true);
        }
        elseif ($prcrec['VALUETYPE']=='PCT_MARKUP') {
                $price=ibcadd($curprice, ibcdiv(ibcmul($curprice, $prcrec['VALUE'], $degree, true), '100', $degree, true), 10, true);
        }
        elseif ($prcrec['VALUETYPE']=='PCT_DISC') {
            $price=ibcsub($curprice, ibcdiv(ibcmul($curprice, $prcrec['VALUE'], $degree, true), '100', $degree, true), 10, true);
        }

        return $price;
    }

    /**
     * Getting ancestors of a product line is a query that can take a LONG time, such as 0.8 seconds on a very small table.
     * Because of this, and because things like Replenishment gets prices over and over, this became a significant bottleneck.
     * So, if cacheing is on, cache the results.
     *
     * @param string $_prodline
     * @param array $priceParams
     *
     * @return string[][]
     */
    private function getAncestorProductLines($_prodline,$priceParams)
    {
        $prodlines = [];

        if ($_prodline != '') {
            if ($this->cacheQueries && isset($this->ancestorCache[$_prodline])) {
                $prodlines = $this->ancestorCache[$_prodline];
            } else {
                $cny       = GetMyCompany();
                $plManager = $priceParams['INVPRICELISTMGR'];
                $prodlines = $plManager->DoQuery('QRY_INVPRICELIST_FETCHLINE_HIER', array($cny, $cny, $_prodline));
                if ($this->cacheQueries) {
                    $this->ancestorCache[$_prodline] = $prodlines;
                }
            }
        }
        return $prodlines;
    }


    /**
     * @param string    $_catalogid
     * @param string    $_productid
     * @param string    $_prodline
     * @param float     $_quantity
     * @param array     $priceParams
     * @param string    $_currency
     *
     * @return array
     */
    function FetchPrice($_catalogid, $_productid, $_prodline, $_quantity, $priceParams, $_currency)
    {
        $cny = GetMyCompany();
        $customFilter = '';
        $orderStr = '';

        $tryForPriceList = true;
        if ($this->cacheQueries && ! isset($this->cachedPriceListItems[$_productid][$_catalogid])) {
            $tryForPriceList = false;   // there cannot be success in the query below
        }

        if ($tryForPriceList) {
            $stmt = array('', $cny, $_catalogid, $_productid, $_quantity, 'Q', $priceParams['FORMATTTED_TIME'], 'T');
            $numArgs = count($stmt);

            if ($priceParams['ISMCPENABLED']) {
                if (!isset($_currency) || $_currency == '') {
                    $_currency = $priceParams['BASECURRENCY'];
                }

                $customFilter .= " and (DECODE(currency, NULL, :" . $numArgs++ . ", currency) = :" . $numArgs++ . " ) ";
                $stmt[] = $priceParams['BASECURRENCY'];
                $stmt[] = $_currency;
            }

            if ($priceParams['EMPLOYEEKEY'] != '') {
                $customFilter .= " and (employeekey = :" . $numArgs . " or employeekey is null) ";
                $orderStr = "( case
                            when employeekey = :" . $numArgs . " then 1 
                            else 2 end
                         ) asc, ";
                $stmt[] = $priceParams['EMPLOYEEKEY'];
            } else {
                $customFilter .= " and employeekey is null ";
            }

            if (IsMCMESubscribed()) {
                $orderStr .= 'currency, ';
            }

            $orderStr .= '(dateto - datefrom) desc, qtylimitmax - qtylimitmin desc';

            $stmt[0] = "select * from (
			SELECT perc, value, decode(valuetype, null, 'ACTUAL', valuetype) as valuetype, sale, fixed
			FROM oeprclstitems 
			WHERE
			   cny# = :1 and
			   prclstkey = :2 and
			   itemkey = :3 and
			   (qtylimitmin <= :4 or qtylimitmin is null) and
			   (qtylimitmax >= :4 or qtylimitmax is null) and            
			   qtyval= :5 and
			   (datefrom <= :6 or datefrom is null) and
			   (dateto >= :6 or dateto is null)  and
			   status = :7
			   $customFilter
			ORDER BY $orderStr
			) where rownum = 1 ";

            $prc = $this->DoOneQuery($stmt) ?? [];

            if ((!empty($prc))) {
                return $prc;
            }
        }

        $prodlines = $this->getAncestorProductLines($_prodline, $priceParams) ?? [];

        // updated code to fix PHP 8.1 error
        $count = is_array($prodlines) ? count($prodlines) : 0;

        if ($count>0) {
            if($priceParams['ISMCPENABLED']) {
                $code = "QRY_INVPRICELIST_FETCHPRICE_MCP_LINE";
                if($_currency == '') {
                    $_currency = $priceParams['BASECURRENCY'];
                }
            } else {
                $code = "QRY_INVPRICELIST_FETCHPRICE_LINE";
            }

            for($i=0; $i<$count; $i++) {
                $prdline=$prodlines[$i]['PRODUCTLINEID'];

                if ($this->cacheQueries && ! isset($this->cachedPriceListProductLines[$prdline][$_catalogid])) {
                    continue;   // there cannot be success in the queries below
                }

                if($priceParams['ISMCPENABLED']) {
                    $args = array ($cny, $_catalogid, $prdline, $_quantity, $_quantity, $priceParams['FORMATTTED_TIME'],$priceParams['FORMATTTED_TIME'], $priceParams['BASECURRENCY'], $_currency);
                } else {
                    $args = array ($cny,$_catalogid,$prdline,$_quantity,$_quantity,$priceParams['FORMATTTED_TIME'],$priceParams['FORMATTTED_TIME']);
                }

                // note that this is similar to the DoOeQuery() logic, but uses the price list manager to get the data, not the standard DoQuery() logic.
                $queryNeeded = true;
                $prc = [];
                if ($this->cacheQueries) {
                    $serializedParameters = serialize($args);
                    if (isset( $this->queryCache[$code][$serializedParameters])) {
                        $this->queryCache[$code][$serializedParameters]['MATCHES']++;  // scored another hit on this entry
                        $prc = $this->queryCache[$code][$serializedParameters]['RESULT'];
                        $queryNeeded = false;
                    }
                }
                if ($queryNeeded) {
                    $plManager =  $priceParams['INVPRICELISTMGR'];
                    $prc = $plManager->DoQuery($code, $args);
                    if ($this->cacheQueries && isset($serializedParameters)) {
                        $this->AddToCache($code,$serializedParameters,$prc);    // yes, cache 'false' returns and empty returns...
                    }
                }

                if ((!empty($prc))) {
                    return $prc;
                }
            }
        }
        $prc = array();
        return $prc;
    }



    /**
     * @param array     $values
     * @param array     $entry
     * @param array     $priceParams
     * @param array     $pl_docpar
     * @param array     $uomInfo
     *
     * @return array
     */
    function PrepDocPriceLineItems($values, $entry, $priceParams, $pl_docpar, $uomInfo)
    {

        $precision = $entry['PRECISION'] ?: DEFAULT_INVPRECISION;
        $productLineID =  $entry['PRODUCTLINEID'] ?: '';

        $price = 0;
        if ($pl_docpar['SALE_PUR_TRANS'] != 'I') {
            $priceMissing = false;
            $price = $this->SuggestPrice(
                $priceParams, $entry['ITEMID'], $productLineID, $entry['UIQTY'], $pl_docpar, $values['CURRENCY'], $priceMissing
            );
            // enable caller to make the distinction between a price of zero and a price that was not found
            $entry['PRICEMISSING'] = $priceMissing ? 'true' : 'false';
            if ($pl_docpar['DISCOUNT_ON_EXTENDEDPRICE'] != 'T') {
                $this->applyDiscount($entry, $price, $uomInfo, $precision);
            }
        }

        $exchRate = (isset($values['EXCHRATE']) && $values['EXCHRATE'] !=='' ) ? $values['EXCHRATE'] : 1;

        $isContractDoc = SODocumentManager::isContractDocument($values);

        $skipPrecision = $isContractDoc;

        if($skipPrecision == false){
            // To skip the applying of precision on document from PGI
            $skipPrecision = $values['fromGenerateInvoices'] ?? false;
        }

        // TODO: for now contract documents do not impliment the precision on UIPRICE / TRX_PRICE
        // untill then skip applying the precision on document from contracts.
        // floatval($entry['UIPRICE']) -- So their may be white spaces before and after the value when value come from API/CSV
        if (isset($entry['UIPRICE']) && $entry['UIPRICE'] !== '' && floatval($entry['UIPRICE']) != 0 && !$skipPrecision) {
            $entry['UIPRICE'] = ibcmul(floatval($entry['UIPRICE']), '1', $precision, true);
        }

        if (!isset($entry['TRX_PRICE']) || $entry['TRX_PRICE'] === '') {
            $entry['TRX_PRICE'] = (isset($entry['UIPRICE']) && $entry['UIPRICE'] !== '') ? $entry['UIPRICE'] : $price;
        }

        // TODO: for now contract documents do not impliment the precision on UIPRICE / TRX_PRICE
        // untill then skip applying the precision on document from contracts.
        // added is_numeric and +$entry['TRX_PRICE'] comparing with 0 to fix PHP 8.1 165245
        if (is_numeric($entry['TRX_PRICE']) && +$entry['TRX_PRICE'] != 0 && !$skipPrecision) {
            $entry['TRX_PRICE'] = ibcmul($entry['TRX_PRICE'], '1', $precision, true);
        }

        // calculate trx value
        if ($pl_docpar['DISCOUNT_ON_EXTENDEDPRICE'] == 'T') {
            if (Util::php7eqEmptyStr($entry['TRX_PRICE'] ?? '')) {
                $entry['TRX_PRICE'] = $price;
            }
            $entry['TRX_VALUE'] = calcValueOnExtendedPrice(
                $entry['UIQTY'], $entry['TRX_PRICE'], $entry['MULTIPLIER'],
                $entry['DISCOUNTPERCENT']
            );
        } else {
            // Note that the TRX_VALUE itself cannot exceed 2 decimal places.
            //  However the UIPRICE may need more precision.
	        $value = ibcmul($entry['TRX_PRICE'], $entry['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
            $entry['TRX_VALUE'] = iround( $value, 2 );  // too wimpy for real precision
        }

        $entry['TRX_ENDVALUE'] = $entry['TRX_VALUE'];
        $entry['UIVALUE'] = ibcmul($entry['TRX_VALUE'], $exchRate, 2, true);

        //recalculate base unit price only for foreign currency transaction
        if ($exchRate != 1) {
            $entry['UIPRICE'] = ibcdiv($entry['UIVALUE'], $entry['QUANTITY'], ItemManager::AVERAGE_COST_DECIMALS, true);
        } else {
            $entry['UIPRICE'] = $entry['TRX_PRICE'];
        }

        $entry['PRICE'] = $entry['UIPRICE'];
        $entry['VALUE'] = $entry['UIVALUE'];
        $entry['ENDVALUE'] = $entry['UIVALUE'];

        if ($values['_DOCPAR']['CONVERT_UNITS'] != 'false' && !isset($values['TIMESHEETITEMS'])) {

            $entry['DECS'][0] = array ('UNIT' => $uomInfo['PUR_UNIT'], 'PRECISION' => $uomInfo['PUR_DEC']) ;
            $entry['DECS'][1] = array ('UNIT' => $uomInfo['STD_UNIT'], 'PRECISION' => $uomInfo['STD_DEC']) ;
            $entry['DECS'][2] = array ('UNIT' => $uomInfo['SAL_UNIT'], 'PRECISION' => $uomInfo['SAL_DEC']) ;

            if (!$uomInfo['CONVFACTOR'] || $uomInfo['CONVFACTOR'] == '') {
                $uomInfo['CONVFACTOR'] = 1;
            }

            $entry['QUANTITY'] = ibcmul($uomInfo['CONVFACTOR'], $entry['QUANTITY'], ItemManager::BASEUNITPRECISION, true);
            $entry['UNITFACTOR'] = $uomInfo['CONVFACTOR'];


            // Primarily the UNITFACTOR Will only be used for conversions is backorders	- update price
            if (isset($entry['UIPRICE'])) {     // prevent absence of a price from being converted into a zero price
                $entry['PRICE'] = ibcdiv($entry['UIPRICE'], $entry['UNITFACTOR'], ItemManager::AVERAGE_COST_DECIMALS, true);
            }
        }

        //IF THE NEW DOCUMENT IS BEING CONVERTED THEN retailprice FROM OLD DOCUMENT, WILL ALREADY COME
        if(isset($entry['RETAILPRICE'])) {

            if( $priceParams['MOD'] == 'so' && $pl_docpar['ENABLE_DISCOUNT_CHARGE'] == 'T') {
                // if the module is so and line item discounts is enabled
                // the retail price will be set in ui based on the
                // sales unit and the pricelist of the child document.

            }else{
                //IN THE NEW DOCUMENT IF ONE OF THESE PRICELIST IS SET, THEN
                if( isset($pl_docpar['PRCLISTKEY']) || isset($pl_docpar['SPCLPRCLISTKEY']) ) {
                    //FETCH THE PRICE SUGGESTED BY PRICE LIST FIRST
                    //NEW retailprice OF THE ITEMS WILL BE SAVED
                    $entry['RETAILPRICE'] = $price;
                }
                //ELSE THE retailprice FROM THE OLD DOCUMENT WILL BE SIMPLY PASSED.
            }
        }else{
            //FETCH THE PRICE SUGGESTED BY PRICE LIST FIRST
            $entry['RETAILPRICE'] = $price;
        }

        return $entry;
    }



    /**
     * @param array     $entry
     * @param float     $price
     * @param array     $uomInfo
     * @param int       $precision
     */
    function applyDiscount(&$entry, $price, $uomInfo, $precision)
    {
        if ((!isset($entry['TRX_PRICE']) || $entry['TRX_PRICE'] === '')
            && (!isset($entry['UIPRICE']) || $entry['UIPRICE'] === '')
        ) {

            $discountedPrice = $price;
            if (!Util::php7eqEmptyStr($discountedPrice) && $discountedPrice !== 0 && isset($entry['DISCOUNTPERCENT'])) {
                $discountAmount = ibcdiv(
                    ibcmul($price, $entry['DISCOUNTPERCENT'], $precision, true),
                    '100', $precision, true
                );
                $discountedPrice = ibcsub(
                    $price, $discountAmount, $precision, true
                );
            }

            if (!Util::php7eqEmptyStr($discountedPrice) && $discountedPrice !== 0 && !empty($uomInfo['CONVFACTOR'])) {
                $discountedPrice = ibcmul(
                    $discountedPrice, $uomInfo['CONVFACTOR'], $precision, true
                );
            }

            $entry['TRX_PRICE'] = $discountedPrice;
        }
    }

    /**
     * Process the item's pricing based on item preferences.
     *
     * @param array $values
     *
     * @return bool
     */
    function UpdateItemPrice(&$values)
    {

        $ok = true;
        //Check for update item in the price list if applicable
        if(!$this->isUpdatePricelist($values['_DOCPAR']['UPDATES_PRICELISTID'], $values['_DOCPAR']['SALE_PUR_TRANS'])) {
            return $ok;
        }

        $this->flushCache();    // hey - we're changing things!

        global $gManagerFactory;
        $itemMgr=    $gManagerFactory->getManager('item');

        foreach ( $values['ENTRIES'] as $key => $entry ) {

            if($values['ISMCPENABLED']) {
                $trx_value = $entry['TRX_PRICE'] * $entry['UIQTY'];
                $price = ibcdiv($trx_value, $entry['QUANTITY'], $entry['PRECISION'], true);
                $currency = $values['CURRENCY'];
            }else{
                $price = $entry['PRICE'];
                $currency='';
            }

            $ok = $ok &&  $itemMgr->SetPrice($entry['ITEMID'], $price, $values['_DOCPAR']['UPDATES_PRICELISTID'], $currency);

            // Make the calculations part of the object
            $values['ENTRIES'][$key] = $entry;
        }

        return $ok;
    }

    /**
     * Check Pricelist entry need to be updated or not.
     *
     * @param string    $updatePricelistId
     * @param string    $salePurTran
     *
     * @return bool
     */
    function isUpdatePricelist($updatePricelistId, $salePurTran)
    {
        $ok = false;
        if ( isset($updatePricelistId) && $updatePricelistId != '' ) {
            $ok = true;
            global $kSFORCEid;
            if ($this->cacheQueries) {
                //For salesforce company
                //If pricing option is set to salesforce with enabled pricelist sync and transaction type is Sale then dont do anything.
                if ($this->salesForceInstalled === NULL) {
                    $this->salesForceInstalled = IsModuleIdInstalled($kSFORCEid);             // do this once
                    if ($this->salesForceInstalled) {
                        GetModulePreferences($kSFORCEid, $this->salesForcePrefs);     // do this once
                    }
                }
                if ($this->salesForceInstalled) {
                    if ((isset($salePurTran) && $salePurTran == 'Sale')
                        && $this->salesForcePrefs['SFORCEPRICELISTSYNC'] == 'true' && $this->salesForcePrefs['SFORCEPRICINGOPT'] == 'S'
                    ) {
                        $ok = false;
                    }
                }
            } else {
                //For salesforce company
                //If pricing option is set to salesforce with enabled pricelist sync and transaction type is Sale then dont do anything.
                if(IsModuleIdInstalled($kSFORCEid)) {
                    GetModulePreferences($kSFORCEid, $prefs);
                    if((isset($salePurTran) && $salePurTran == 'Sale')
                        && $prefs['SFORCEPRICELISTSYNC'] == 'true' && $prefs['SFORCEPRICINGOPT'] == 'S'
                    ) {
                        $ok = false;
                    }
                }
            }
        }
        return $ok;
    }

}


