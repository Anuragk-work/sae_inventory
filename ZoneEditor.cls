<?php
/**
 * =============================================================================
 *
 * FILE:        AisleEditor.cls
 * AUTHOR:      
 * DESCRIPTION:    
 *
 * (C)2000,2009 Intacct Corporation, All Rights Reserved
 *
 * Intacct Corporation Proprietary Information.
 * This document contains trade secret data that belongs to Intacct
 * corporation and is protected by the copyright laws. Information herein
 * may not be used, copied or disclosed in whole or part without prior
 * written consent from Intacct Corporation.
 * =============================================================================
 */

/**
 * Editor class for ZoneEditor object
 */
class ZoneEditor extends FormEditor
{
     /**
     * @param array $_params Initial params
     */
    public function __construct($_params = array())
    { 
        parent::__construct($_params); 
    }

    /**
     * @param string $state
     *
     * @return array
     */
    public function getStandardButtons($state)
    {
        switch ($state) {
            case Template_CreateWarningState:
            case Editor_ShowNewState:
                $values = $this->createNewButtons();
                break;
            case Template_EditWarningState:
            case Editor_ShowEditState:
                if( $this->CanSave() ) {
                    $this->setButtonDetails($values, Editor_SaveBtnID, 'dobutton', $this->getLabelForSaveButton(), 'save');
                }

                if ($this->CanDuplicate()) {
                    $this->setButtonDetails($values, 'savebutton', 'copybutton', 'IA.DUPLICATE', 'copy', true, 'window.editor.prepareForDuplicate()', true, true);
                }

                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }
                // doesn't seem to be used in the php editor and its action is not right $this->setButtonDetails($values, 'saveandprintbutton', 'Save & Print', 'save');
                if( $this->CanPrint() ) {
                    $this->createMoreActionEntry($values, 'saveandprintbuttid', 'deliverbutton', 'IA.PRINT_TO', 'deliver', false, "showDeliverPageNew(true, data)", false, false);
                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false);
                break;
            case Editor_ShowViewState:
                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }

                if( $this->CanPrint() ) {
                    $this->createMoreActionEntry($values, 'saveandprintbuttid', 'deliverbutton', 'IA.PRINT_TO', 'deliver', false, "showDeliverPageNew(true, data)", false, false);
                }

                if($this->CanEdit()) {
                    $this->setButtonDetails($values, 'editbuttid', 'editbutton', 'IA.EDIT', 'edit', false, 'window.editor.doEdit()', false);
                }

                if ($this->CanDuplicate()) {
                    $this->setButtonDetails($values, 'savebutton', 'copybutton', 'IA.DUPLICATE', 'copy', true, 'window.editor.prepareForDuplicate()', true, true);
                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.DONE', 'cancel', false);
                break;
        }

        $this->addHelpButton($values);
        return $values;
    }

    /**
     * Creates create and cancel buttons for new form state.
     *
     * @return array buttons
     */
    protected function createNewButtons()
    {
        $values = array();
        if ($this->CanSave()) {
            $buttonsProperty = array(
                'IA.SAVE' => array(
                    'action' => 'create',
                    'isSaveNew' => false,
                    'isDefault' => true,
                    'id' => Editor_SaveBtnID
                ),
                'IA.SAVE_AND_NEW' => array(
                    'action' => 'create',
                    'isSaveNew' => true,
                    'isDefault' => false,
                    'id' => Editor_SaveAndNewBtnID
                ),
            );
            $this->createSplitButtonEntry($values, $buttonsProperty);
        }
        $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', 'IA.CANCEL', 'cancel', false);
        return $values;
    }

    /**
     * @param array $buttons
     * @param array $buttonsProperty
     */
    protected function createSplitButtonEntry( &$buttons, $buttonsProperty )
    {
        $actions = array();
        foreach ($buttonsProperty as $buttonkey => $buttonproperty) {
            //$action = array();

            $action = $this->createAction(
                $buttonproperty['id'], 'saveandnewbutton_' . $buttonproperty['id'], $buttonkey,
                $buttonproperty['action'], true
            );

            if (isset($buttonproperty['isSaveNew']) && $buttonproperty['isSaveNew'] == true) {
                $action = $this->createAction(
                    $buttonproperty['id'], 'saveandnewbutton_' . $buttonproperty['id'], $buttonkey,
                    $buttonproperty['action'], true, null, true, false, array('after' => 1)
                );
            }
            if (isset($buttonproperty['isDefault']) && $buttonproperty['isDefault'] == true ) {
                $action['default'] = true;
            }
            $actions[] = $action;
        }
        $this->createSplitButton($buttons, $actions);
    }

}

