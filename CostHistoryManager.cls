<?php

/**
 * Manager class for Cost History
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Manager class for cost history
 */
class CostHistoryManager extends EntityManager
{

    /**
     * __construct
     *
     * @param array $params entitymanager param
     */
    function __construct($params = array())
    {
        parent::__construct($params);
    }

    /**
     * @param string $item
     * @param string $warehouse
     * @param string $date
     *
     * @return array
     */
    public function getcosthistory($item, $warehouse, $date)
    {
        $params = array(
            'filters' => array(
                array(
                    array('ITEMKEY', '=', $item),
                    array('WHSEKEY', '=', $warehouse),
                    array('ASON', '<=', $date),
                )
            ),
            'orders' => array(array('ASON', 'desc')),
        );

        $costHistory = $this->GetList($params);

        return $costHistory[0];
    }
}