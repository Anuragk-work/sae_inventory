<?php
/**
 * =============================================================================
 *
 * @filesource  CostEditor.cls
 * @author
 * @copyright 2000,2009, Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */

/**
 * class CostEditor extends FormEditor
 */
class InvCostToolEditor extends FormEditor
{
    /**
     * @param string[] &$_params array
     */
    function __construct(&$_params)
    {
        parent::__construct($_params);

        $this->addFetchAction();
        $this->addFixAction();
        $this->addDownloadAction();
    }

    /**
     * getJavaScriptFileNames
     *
     * @return array returns array
     */
    protected function getJavaScriptFileNames()
    {
        return array(
            '../resources/js/invcost.js',
        );
    }

    /**
     * @return InvCostToolManager
     */
    public function getEntityMgr()
    {
        /**
         * @var InvCostToolManager $em;
         */
        $em = $this->entityMgr;
        return $em;
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $this->getEntityMgr()->fetchLog($obj);

        return true;
    }

    /**
     * getStandardButtons
     *
     * @param array $state parameters
     *
     * @return array $buttons to display
     */
    public function getStandardButtons($state)
    {
        $buttons = array();
        $this->setButtonDetails($buttons, 'fetchbuttonid', 'fetch', 'IA.PERFORM_ANALYSIS', 'fetch', true, "fetchData(this)", true, false, array('fetch' => 1));
        $this->setButtonDetails($buttons, 'fetchbuttonid', 'fix', 'IA.PROCESS_AND_FIX', 'fix', true, "fixData(this)", true, false, array('fix' => 1));
        $this->setButtonDetails($buttons, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false);
        return $buttons;
    }

    /**
     * addFetchAction
     */
    protected function addFetchAction()
    {
        $this->kActionHandlers['fetch'] = array(
            'handler' => 'FetchItemDataAction',
            'states' => array(
                $this->kShowEditState,
                $this->kShowViewState,
                $this->kShowNewState,
            )
        );
    }

    /**
     * addFixAction
     *
     */
    protected function addFixAction()
    {
        $this->kActionHandlers['fix'] = array(
            'handler' => 'FetchValuationDataAction',
            'states' => array(
                $this->kShowEditState,
                $this->kShowViewState,
                $this->kShowNewState,
            )
        );
    }

    /**
     * addDownloadAction
     *
     */
    protected function addDownloadAction()
    {
        $this->kActionHandlers['download'] = array(
            'handler' => 'downloadCSV',
            'states' => array(
                $this->kShowEditState,
                $this->kShowViewState,
                $this->kShowNewState,
            )
        );
    }

    /**
     * @param array $obj
     */
    protected function downloadCSV(&$obj)
    {
        if ($obj['DOWNLOAD']) {
            $this->getEntityMgr()->downloadCSV($obj);
            unset($obj['DOWNLOAD']);
        }
    }

    /**
     * runAjax
     *
     * @param string $cmd parameters
     *
     * @return bool
     */
    protected function runAjax($cmd)
    {
        $ok = parent::runAjax($cmd);        // php71 note: even though it COULD return false, I don't know that we shouldn't keep going....
        $list = $this->runajaxFilter($cmd);
        echo json_encode($list);
        return $ok;
    }

    /**
     * @param string $cmd parameters
     *
     * @return string|array
     */
    protected function runajaxFilter($cmd)
    {
        $data = Request::$r->_data;
        if ($data) {
            $obj = Util_DataRecordFormatter::jsonToPhp($data);
            switch ($cmd) {
                case "fetch":
                    $this->getEntityMgr()->fetchAction($obj);
                    break;
                case "fix":
                    $this->getEntityMgr()->fixAction($obj);
                    break;
            }
            $this->getEntityMgr()->fetchLog($obj);
            return $obj['LOG'];
        }
        $list = array();
        return $list;
    }


    /**
     * @param array  $_params
     * @param bool   $offline
     * @param string &$out
     *
     * @return bool
     */
    public function Editor_Deliver(&$_params, $offline, &$out)
    {
        $obj = $this->getViewData();

        $method = Request::$r->_deliverymethod;
        if ($obj['DOWNLOAD']) {
            $method = 'csv';
        } else if (!$method) {
            $method = 'pdf';
        }

        switch ($method) {
            case 'csv' :
                $this->downloadCSV($obj);
                break;
            case 'xmldata' :
            case 'phpdata' :
            case 'xmlform' :
            case 'phpform' :
            case 'xsl' :
            case 'fo' :
            case 'pdf' :
                parent::Editor_Deliver($_params, $offline, $out);
                break;

        }
        return true;
    }


}
