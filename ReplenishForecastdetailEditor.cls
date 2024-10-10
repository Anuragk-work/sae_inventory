<?php
/**
 * =============================================================================
 *
 * @filesource ReplenishmentEditor.cls
 * @author
 * @copyright  2018, Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */


/**
 * class ReplenishmentEditor extends FormEditor
 */
class ReplenishForecastdetailEditor extends FormEditor
{

    /**
     * {{{ Constructor
     *
     * @param array $_params
     */
    function __construct($_params = [])
    {
        parent::__construct($_params);

    }


    /**
     * Delivers current record in online as well as offline mode
     *
     * @param array $_params
     *
     * @return bool
     */
    function Editor_Export(/** @noinspection PhpUnusedParameterInspection */
        &$_params)
    {
        $entity = Request::$r->_it;
        $itemid = Request::$r->item;


        global $gManagerFactory;
        $mgr = $gManagerFactory->getManager($entity);

        $csvdata = $mgr->exportItemAsCSV($itemid);

        $suffix = '.csv';
        $filename = filename_safe('forecast_' . $itemid) . $suffix;
        header("Content-type: application/msword");
        header("Content-Disposition: filename=\"$filename\"");
        header("Content-Length: " . strlen($csvdata));
        echo($csvdata);

        return true;

//        jq('.pace') . addClass('pace-inactive') . removeClass('pace-active');


    }

}


