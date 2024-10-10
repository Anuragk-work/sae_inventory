<?php
/**
 * Manager file for the standard object replenishForecast
 *
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation All, Rights Reserved
 */


/**
 * @category  Cls
 * @package   Source/inventory
 * @author    Roger Collins
 * @copyright 2018 Intacct Corporation, All Rights Reserved
 */
class ReplenishForecastManager extends EntityManager
{


    /**
     * @param array $params List of parameters for specific to this object
     */
    function __construct($params = array())
    {
        parent::__construct($params);

    }


    /**
     * Get a single record
     *
     * @param string        $ID
     * @param string[]|null $fields
     *
     * @return array|false
     */
    public function Get($ID, $fields = null)
    {
        list($ID) = explode('--', $ID);
        $toreturn = parent::get($ID);

        if (is_array($toreturn) && empty($toreturn['STATUS']))
        {
            // set any empty status values to 'inactive'
            $toreturn['STATUS'] = 'Inactive';
        }
        return $toreturn;
    }


    /**
     * Return a list of entities
     *
     * @param array $params    a structure used to build the custom query
     * @param bool  $_crosscny if true do not add the var.cny# = ... code
     * @param bool  $nocount   don't generate a count column
     *
     * @return array[] $newResult  result of query
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        $result = parent::GetList($params, $_crosscny, $nocount);
        //fetch and add componet details
        foreach ($result as $key => $headerrec)
        {
            $detailrec = $this->Get($headerrec['RECORDNO']);
            if (isset($detailrec['ITEMID']) && $detailrec['ITEMID'] != '')
            {
                $result[$key]['REPLENISH_FORECAST_ENTRIES_INFO'] = $detailrec['REPLENISH_FORECAST_ENTRIES_INFO'];
            }
        }

        return $result;
    }


    /**
     * add a record to the database
     *
     * @param array &$values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $result = QueryResult(["select  record# from replenishforecasthdr where  ITEMID = :1 and cny# = :2",
                $values['ITEMID'], GetMyCompany()]
        );

        if (count ($result) == '0')
        {
            if (!$this->validateItem($values['ITEMID'])) {
                return false;
            }
            return parent::regularAdd($values);
        }
        else
        {
            $values['RECORDNO'] = $result[0]['RECORD#'] ;
            return parent::regularSet($values);
        }
    }

    /**
     * @param $values
     * Validates the item on server side (esp. for REST)
     * @return bool
     */
    private function validateItem(string $itemID): bool
    {
        global $gErr;
        $ok =true;

        $qry = "select it.itemid, it.status, it.itemtype, it.enable_replenishment
                from icitem it
                where it.cny#=:1 and it.itemid=:2";

        $result = QueryResult(array($qry,GetMyCompany(),$itemID));
        if ($result) {
            if( $result[0]['STATUS'] != 'T' ) {
                $gErr->addIAError('INV-1456', GetFL(), "Item is inactive", [],
                                  "", [],'Pick a valid active item',[]);

                $ok = false;
            }else if (!($result[0]['ITEMTYPE'] == 'I' || $result[0]['ITEMTYPE']== 'SK')){
                $gErr->addIAError('INV-1457', GetFL(), "Only Inventory or Stockable kit items are supported for Replenishment", [],
                                  "", []);
                $ok = false;
            }
            else if($result[0]['ENABLE_REPLENISHMENT'] != 'T') {
                $gErr->addIAError('INV-1458', GetFL(), "Item is not enabled for Replenishment", [],
                                  "", []);
                $ok = false;
            }
        }else{
            $gErr->addIAError('INV-0747', GetFL(), "Item - '$itemID' doesnt exist", [],
                              "",[]);
            $ok = false;
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
        return parent::regularSet($values);
    }

    /**
     * @param array &$values
     * @return bool
     */
    function AddOrUpdate(&$values)
    {
        $ok = $this->add($values);

        return $ok;
    }


    }

