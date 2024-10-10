<?php

/* File header
*	FILE: ICCycleCountLister.cls
*	AUTHOR: shreerajath Hebbar <shreerajath.hebbar@sage.com>
*	DESCRIPTION: ICCycleCountLister is lister class for ICCycleCount
*
*	(C) 2020, Intacct Corporation, All Rights Reserved
*
*	This document contains trade secret data that belongs to Intacct
*	Corporation and is protected by the copyright laws.  Information
*	herein may not be used, copied or disclosed in whole or in part
*	without prior written consent from Intacct Corporation.
*/

class ICCycleCountLister extends NLister
{
    protected $additionalTokens = [
        "IA.INVENTORY_TOTALS","IA.START_COUNT","IA.RESUME_COUNT","IA.RECONCILE","IA.VIEW_RECONCILIATION"
    ];
    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'iccyclecount',
            'title'            => 'IA.CYCLE_COUNTS',
            'fields'        =>  array('CYCLECOUNTID', 'CYCLECOUNTDESC', 'WAREHOUSEID', 'EMPUSERID', 'COUNTENDDATE',
                                      'COUNTSTATE','LINESINCOUNT', 'ADJUSTMENTCOUNT', 'ADJUSTMENTDATE', "'ACTION'", "'RECONCILE'"),
            // the list of fields which need special encoding
            'nonencodedfields' => array('RECORD_URL', "'ACTION'", "'RECONCILE'"),
            'helpfile'        => 'Viewing_and_Managing_the_CycleCount_List',
            'enablemultidelete' => true,
            'sortcolumn'    => 'RECORDNO:d, CYCLECOUNTID:d',
            )
        );
    }

    function BuildTable() {

        parent::BuildTable();

        $table = &$this->table;

        $op = GetOperationId('inv/lists/iccyclecount/edit');
        $_sess = Session::getKey();
        $editPermission = CheckAuthorization($op);

        $reconcileOP = GetOperationId('inv/lists/iccyclecount/reconcile');
        $reconcilePermission = CheckAuthorization($reconcileOP);

        foreach ($table as $key => $tableEntry) {
            $startcount = '';
            $action = '';
            $owner = $this->GetObjectOwnership($key);
            $ownerloc = $this->GetObjectOwnerLocation($key);

            $table[$key]["'ACTION'"] = '';
            $table[$key]["'RECONCILE'"] = '';
            if($tableEntry['LOCLEVEL'] != -1){
                if($editPermission){
                    if( isset($tableEntry['COUNTSTATE']) && $tableEntry['COUNTSTATE'] !== ICCycleCountFormEditor::STATE_COUNTED){

                        if( $tableEntry['COUNTSTATE'] === ICCycleCountFormEditor::STATE_NOTSTARTED ){
                            $startcount = GT($this->textMap, 'IA.START_COUNT');
                            $action = "&.action=listerstartcount";
                        } else if ( $tableEntry['COUNTSTATE'] === ICCycleCountFormEditor::STATE_INPROGRESS ){
                            $startcount = GT($this->textMap, 'IA.RESUME_COUNT');
                        }

                        $url = "editor.phtml?.do=edit&.it=iccyclecount&.r=". urlencode($tableEntry['RECORDNO']) ."&.op=$op"
                            . "&.sess=".urlencode($_sess)."&" .OptDone(ScriptRequest()).$action;
                        if($owner > 0 && $ownerloc) {
                            $url = $this->_calcSlideUrl($url, $ownerloc);
                        }
                        $url = "<a href=\"" . $url . "\">$startcount</a>";
                        $table[$key]["'ACTION'"] = $url;
                    }
                }

                $states = [ ICCycleCountFormEditor::STATE_COUNTED, ICCycleCountFormEditor::STATE_VOIDED,
                    ICCycleCountFormEditor::STATE_RECONCILED ];

                if($reconcilePermission && isset($tableEntry['COUNTSTATE'])
                          && in_array($tableEntry['COUNTSTATE'], $states)){

                    if(isset($tableEntry['COUNTSTATE']) && $tableEntry['COUNTSTATE'] == ICCycleCountFormEditor::STATE_COUNTED){
                        $reconcileCount = GT($this->textMap, 'IA.RECONCILE');
                        $action = "&.do=edit";
                    }else{
                        $reconcileCount = GT($this->textMap, 'IA.VIEW_RECONCILIATION');
                        $action = "&.do=view";
                    }

                    $reconcileUrl = "editor.phtml?.it=iccyclecount&.r=". urlencode($tableEntry['RECORDNO']) ."&.op=$op"
                        . "&.sess=".urlencode($_sess)."&" .OptDone(ScriptRequest())."&.reconcile=true".$action;
                    if($owner > 0 && $ownerloc) {
                        $reconcileUrl = $this->_calcSlideUrl($reconcileUrl, $ownerloc);
                    }
                    $reconcileUrl = "<a href=\"" . $reconcileUrl . "\">$reconcileCount</a>";
                    $table[$key]["'RECONCILE'"] = $reconcileUrl;

                }
            }
        }
    }

    /**
     * Method to return the edit url string
     * @param int $i
     * @param array $vals
     * @return array
     */
    public function calcEditUrlParms($i,$vals)
    {
        $table = &$this->table;
        $states = [ ICCycleCountFormEditor::STATE_COUNTED, ICCycleCountFormEditor::STATE_VOIDED,
            ICCycleCountFormEditor::STATE_RECONCILED ];
        if( isset($table[$i]['COUNTSTATE']) && in_array($table[$i]['COUNTSTATE'], $states)) {
            return [];
        }

        return parent::calcEditUrlParms($i,$vals);
    }

    /**
     * @param int         $i
     * @param string|null $owner
     * @param string|null $ownerloc
     * @param bool|null   $ownedObj
     *
     * @return string
     */
    function calcDeleteUrl($i, $owner = null, $ownerloc = null, $ownedObj = null)
    {
        $table = &$this->table;
        $states = [ ICCycleCountFormEditor::STATE_COUNTED, ICCycleCountFormEditor::STATE_VOIDED,
            ICCycleCountFormEditor::STATE_RECONCILED ];
        $deleteValue = parent::calcDeleteUrl($i);

        if( isset($table[$i]['COUNTSTATE'])
            && in_array($table[$i]['COUNTSTATE'], $states) && $deleteValue !== 'Not Owned') {
            return false;
        }

        return $deleteValue;
    }

}


