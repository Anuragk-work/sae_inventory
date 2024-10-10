<?php
/**
 * File ReplenishmentRunEditor.cls contains the class ReplenishmentRunEditor
 *
 * @author
 * @copyright 2000-2018 Intacct Corporation
 *
 * This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Intacct Corporation.
 */

/**
 * Replenishment run editor
 *
 * Class ReplenishmentRunEditorEditor
 */
class ReplenishmentRunEditor extends FormEditor
{
    /**
     * @param array $params The parameters of the class
     */
    public function __construct($params = [])
    {
        parent::__construct($params);

    }

     /**
     * Forms drill-down links etc.
     *
     * @param array $obj Short-listed records
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        //Create url links for generated PO's
        $poMgr = null;
        foreach ($obj['REPLENISHRUN_DETAIL'] as &$aRow) {
            if ($poMgr == null) {
                $poMgr = Globals::$g->gManagerFactory->getManager('podocument');
            }
            $poDoc = $poMgr->get($aRow['TRANSACTION_ID']);
            if (!$poDoc) {
                //Postpend "(deleted)" the PO doc ID if we can't get the PO
                if (isset($aRow['TRANSACTION_ID'])) {
                    $aRow['TRANSACTION_ID'] = $aRow['TRANSACTION_ID'] ." (deleted)";
                }
            } else {
                //Create url link to PO doc
                $sess = Session::getKey();
                $po_viewopid = GetOperationId("po/lists/podocument/view");
                $po_url =
                    "editor.phtml?.do=view"
                    . "&.sess=" . $sess
                    . "&.op=" . $po_viewopid
                    . "&.dt=" . urlencode($obj['TRANSACTION_DEFINITION'])
                    . "&.r=" . urlencode(urlencode($aRow['TRANSACTION_ID']));   //I had to double encode somehow otherwise the request
                                                                                //payload stripped everything after '#'. If I don't double encode,
                                                                                //"Purchase Order-PO#0166#doc" will be sent as "Purchase Order-PO".
                $po_ref =
                    '<a href=\'javascript:Launch( "'
                    . $po_url
                    . '" , "podocument");\' target1="_blank">'
                    . $aRow['TRANSACTION_ID']
                    . '</a>';
                $aRow['TRANSACTION_ID'] = $po_ref;
            }
        }

        return true;
    }

    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        $buttons = array();
        $this->setButtonDetails($buttons, Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false);

        return $buttons;
    }

    /**
     * Method getJavaScriptFileNames - get list of required client-side script files
     *
     * @return array of required javascript files to be included
     */
    protected function getJavaScriptFileNames()
    {
        $jsfiles = array("../resources/js/replenishmentrun.js");
        return $jsfiles;
    }

    /**
     * I18N. Collection of tokens used primarily in JavaScript.
     *
     * @return string[]
     */
    protected function getFormTokens() : array
    {
        $this->textTokens[] = 'IA.SUCCESS';
        $this->textTokens[] = 'IA.PARTIALSUCCESS';
        $this->textTokens[] = 'IA.INQUEUE';
        $this->textTokens[] = 'IA.WARNINGS';
        $this->textTokens[] = 'IA.POSTED';
        $this->textTokens[] = 'IA.CREATED';
        $this->textTokens[] = 'IA.FAILED';
        $this->textTokens[] = 'IA.ONLINE';
        $this->textTokens[] = 'IA.OFFLINE';
        return parent::getFormTokens();
    }
}