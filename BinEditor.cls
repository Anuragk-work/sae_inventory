<?php
/**
 * =============================================================================
 *
 * FILE:        BinEditor.cls
 * AUTHOR:      Sri Vidya
 * DESCRIPTION: Editor class for handelling Bin object
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
 * Editor class for Bin object
 */
class BinEditor extends FormEditor
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
                    $this->setButtonDetails($values, 'savebutton', 'copybutton', "IA.DUPLICATE", 'copy', true, 'window.editor.prepareForDuplicate()', true, true);
                }

                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }
                // doesn't seem to be used in the php editor and its action is not right $this->setButtonDetails($values, 'saveandprintbutton', 'Save & Print', 'save');
                if( $this->CanPrint() ) {
                    $this->createMoreActionEntry($values, 'saveandprintbuttid', 'deliverbutton', "IA.PRINT_TO", 'deliver', false, "showDeliverPageNew(true, data)", false, false);
                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', "IA.CANCEL", 'cancel', false);
                break;
            case Editor_ShowViewState:
                if ($this->CanShowAuditTrail()) {
                    $this->configureAuditTrailButton($values);
                }

                if( $this->CanPrint() ) {
                    $this->createMoreActionEntry($values, 'saveandprintbuttid', 'deliverbutton', "IA.PRINT_TO", 'deliver', false, "showDeliverPageNew(true, data)", false, false);
                }

                if($this->CanEdit()) {
                    $this->setButtonDetails($values, 'editbuttid', 'editbutton', "IA.EDIT", 'edit', false, 'window.editor.doEdit()', false);
                }

                if ($this->CanDuplicate()) {
                    $this->setButtonDetails($values, 'savebutton', 'copybutton', "IA.DUPLICATE", 'copy', true, 'window.editor.prepareForDuplicate()', true, true);
                }
                $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', "IA.DONE", 'cancel', false);
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
                _("Save") => array(
                    'action' => 'create',
                    'isSaveNew' => false,
                    'isDefault' => true,
                    'id' => Editor_SaveBtnID
                ),
                _("Save & new") => array(
                    'action' => 'create',
                    'isSaveNew' => true,
                    'isDefault' => false,
                    'id' => Editor_SaveAndNewBtnID
                ),
            );
            $this->createSplitButtonEntry($values, $buttonsProperty);
        }
        $this->setButtonDetails($values, Editor_CancelBtnID, 'cancelbutton', "IA.CANCEL", 'cancel', false);
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


    /**
     *      Change a property of a list of sections or grids or fields
     *
     * @param string        $type       EditorComponentFactory::TYPE_GRID or EditorComponentFactory::TYPE_SECTION or ...
     * @param string[]      $list       The array of ids or paths to hide
     * @param string        $property   The property to set
     * @param string|bool   $value      The value to set
     */
    private function setProperty($type, $list, $property, $value)
    {
        $view = $this->getView();
        $fieldType = ($type == EditorComponentFactory::TYPE_SECTION) ? 'id' : 'path';
        foreach ($list as $field) {
            $obj = [];
            $view->findComponents([$fieldType => $field], $type, $obj);
            if (isset($obj[0])) {
                $obj[0]->setProperty($property, $value);
            }
        }
    }


    /**
     *      hide a list of sections or grids or fields
     *
     * @param string    $type       EditorComponentFactory::TYPE_GRID or EditorComponentFactory::TYPE_SECTION or ...
     * @param string[]  $list       The array of ids or paths to hide
     */
    private function hide($type, $list)
    {
        $this->setProperty($type, $list, 'hidden', true);
    }


    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        $state = $this->getState();
        $advanceBinEnabled = BinManager::areAdvanedBinsOn();
        if ($advanceBinEnabled) {
            $warehouseEdit = ($state == $this->kShowNewState);
            $this->setProperty(EditorComponentFactory::TYPE_FIELD, ['WAREHOUSEID'], 'required', $warehouseEdit);
            $this->setProperty(EditorComponentFactory::TYPE_FIELD, ['WAREHOUSEID'], 'readonly', ! $warehouseEdit);
            $this->setProperty(EditorComponentFactory::TYPE_FIELD, ['BINID'], 'readonly', ($state == $this->kShowViewState));
        } else {
                // hide the advanced fields
            $this->hide(EditorComponentFactory::TYPE_FIELD,
                    ['ZONEID', 'FACEID', 'STATUS', 'AISLEID', 'SIZEID', 'PORTABLE', 'WAREHOUSEID', 'ROWID', 'SEQUENCENO']);
        }

        // This will show the bin items inevntory details only in view mode
        $this->mediateDataAndMetadata_binInventory($obj, $advanceBinEnabled);

        return true;
    }

    /**
     * @param array $obj
     * @param bool $advanceBinEnabled
     */
    private function mediateDataAndMetadata_binInventory(&$obj, $advanceBinEnabled)
    {
        $state = $this->getState();
        if (isset($state) && $state == $this->kShowViewState && $advanceBinEnabled) {
            $view = $this->getView();
            $binPage = [];
            $view->findComponents(['id' => 'binitemsinventory'], EditorComponentFactory::TYPE_TAB, $binPage);
            if (isset($binPage[0])) {
                $binPage[0]->setProperty('hidden', false);

                $binMgr = Globals::$g->gManagerFactory->getManager('bin');
                $obj['BINITEMSINEVNTORY'] = $binMgr->getBinInventory($obj['RECORDNO']);
            }
        }
    }

    /**
     *      Override of FormEditor::getEntityId() used by the audit trail.  If in Advanced mode, we tell
     *  the manager to use the special 'Audit Trail Vid' (record#)
     *
     * @return string|mixed
     *
     */
    protected function getEntityId()
    {
        // inspections don't like $this->getEntityMgr() for some reason....
        $manager = Globals::$g->gManagerFactory->getManager('bin');
        $priorUseAuditTrailVid = $manager->useAuditTrailVid;   // in case we nest
        if (BinManager::areAdvanedBinsOn()) {
            $manager->useAuditTrailVid = true;
        }
        $viewData = parent::getEntityId();
        $manager->useAuditTrailVid = $priorUseAuditTrailVid;
        return $viewData;
    }

}
