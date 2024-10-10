<?php

/* File header
*	FILE: ICCycleCountReport.cls
*	AUTHOR: shreerajath Hebbar <shreerajath.hebbar@sage.com>
*	DESCRIPTION: ICCycleCountReport is reporter class
*
*	(C) 2020, Intacct Corporation, All Rights Reserved
*
*	This document contains trade secret data that belongs to Intacct
*	Corporation and is protected by the copyright laws.  Information
*	herein may not be used, copied or disclosed in whole or in part
*	without prior written consent from Intacct Corporation.
*/

class ICCycleCountReport extends GroupReporter
{

    /**
     * @var array $_cycleCountData
     */
    var $_cycleCountData = [];

    /**
     * @param array $params
     */
    function __construct($params)
    {
        parent::__construct(
            INTACCTarray_merge(
                $params, array(
                    'title' => 'IA.CYCLE_COUNT_REPORT',
                    'report' => 'iccyclecount',
                    '2stage' => true,
                )
            )
        );

        if (IsMCMESubscribed()) {
            $this->params['NOREPORTLOCCHECK'] = true;
        }
    }

    /**
     * @return bool
     */
    function DoQuery()
    {
        $gManagerFactory    = Globals::$g->gManagerFactory;
        $cycleCountRecordNo = Request::$r->_cycleCountRecordNo;

        if(isset($cycleCountRecordNo) && $cycleCountRecordNo != ''){
            $cycleCountMgr = $gManagerFactory->getManager('iccyclecount');
            $this->_cycleCountData =  $cycleCountMgr->get($cycleCountRecordNo);
        }

        return true;
    }

    /**
     * @return array
     */
    function DoMap()
    {
        $lines = $this->prepareHeader();
        $lines = $this->prepareBody($lines);
        return $lines;
    }

    /**
     * @return bool
     */
    public function canSaveReportPref()
    {
        $cansave = true;
        $drillfilter = Request::$r->_drillfilter;
        if ( isset($drillfilter) && $drillfilter == '1' ) {
            // incase of drilldown, we should not save the preference on the fly.
            $cansave = false;
        }
        return $cansave;
    }

    /**
     * prepareHeader for ptinting the document
     *
     * @return array
     */
    function prepareHeader()
    {
        $kINVid = &Globals::$g->kINVid;
        GetModulePreferences($kINVid, $invPrefs);
        $cycleCountData = $this->_cycleCountData;
        $state = $cycleCountData['COUNTSTATE'];

        if ($state == ICCycleCountFormEditor::STATE_COUNTED_VALUE){
            $lines['report'][0]['title'] = 'Cycle count variance report';
            $this->params['title'] = $cycleCountData['CYCLECOUNTID']. "_cycle_count_report";
        } else {
            $lines['report'][0]['title'] = 'Cycle count variance report-Draft';
            $this->params['title'] = $cycleCountData['CYCLECOUNTID']. "_worksheet";
        }

        //$lines['report'][0]['titlecomment'] = 'Cycle Count Data';
        $lines['report'][0]['op']    =  $this->params['op'];
        $lines['report'][0]['sess']  =  $this->params['sess'];
        $lines['report'][0]['co']    = GetMyCompanyName();
        $lines['report']['0']['companyid'] = GetMyCompany();
        $lines['report']["0"]['reportdate']     = GetCurrentDate(IADATE_USRFORMAT);
        if(Profile::getUserCacheProperty('USERPREF', 'TIMEFORMAT') == 'HH24:MI:SS') {
            $lines['report']["0"]['reporttime'] = date("G:i T");
        } else {
            $lines['report']["0"]['reporttime']     = date("g:i A T");
        }
        $lines['report']['0']['report_format'] = $this->params['type'];

        //Check for On Hand qty to display or not based on the selection.
        $lines['report'][0]['qtyonhand'] =  'N';
        if(isset($state) && $state == ICCycleCountFormEditor::STATE_COUNTED_VALUE){
            $lines['report'][0]['variancefields'] =  'Y';
            $lines['report'][0]['displayvariancefields'] = 'true';
        }

        //Checke for Bin tracking enabled so that we can show that fields in XSL.
        $lines['report'][0]['displaybin'] = ($invPrefs['ENABLEBIN'] == 'T') ? 'true' : 'false';

        //Checke for Serial tracking enabled so that we can show that fields in XSL.
        $lines['report'][0]['displayserialno'] = ($invPrefs['ENABLESERIAL'] == 'T') ? 'true' : 'false';

        //Checke for Lot tracking enabled so that we can show that fields in XSL.
        $lines['report'][0]['displaylotno'] = ($invPrefs['ENABLELOT'] == 'T') ? 'true' : 'false';

        //Checke for Expiration tracking enabled so that we can show that fields in XSL.
        $lines['report'][0]['displayexpdate'] = ($invPrefs['ENABLE_EXPIRATION'] == 'T') ? 'true' : 'false';

        return $lines;
    }

    /**
     * @param array $lines
     *
     * @return array
     */
    function prepareBody($lines)
    {
        $cycleCountData = $this->_cycleCountData;
        if (count($cycleCountData)==0) {
            $lines['report'][0]['NODATA'][0]= array('NODATA'=>'1');
        } else {
            $lines['report'][0]['CYCLECOUNTDATA'] = $cycleCountData;
        }
        return $lines;
    }

}
