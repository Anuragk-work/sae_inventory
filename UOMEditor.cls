<?php

/**
 * =============================================================================
 *
 * FILE:        UOMEditor.cls
 * AUTHOR:        Shone Chacko
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

class UOMEditor extends FormEditor
{
    /**
     * @param array $_params
     */
    function __construct($_params=array())
    {
        parent::__construct($_params);
    }

    /**
     * @param array $obj
     *
     * @return mixed
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        parent::mediateDataAndMetadata($obj);
        $view = $this->getView();

        //hide the default UOMS when creating a new UOM
        if ($this->state == Editor_ShowNewState) {
            $hiddenfields = array();
            $view->findComponents(array('path' => 'INVUOM'), EditorComponentFactory::TYPE_FIELD, $hiddenfields);
            $view->findComponents(array('path' => 'POUOM'), EditorComponentFactory::TYPE_FIELD, $hiddenfields);
            $view->findComponents(array('path' => 'OEUOM'), EditorComponentFactory::TYPE_FIELD, $hiddenfields);
            $view->findComponents(array('path' => 'DEFAULTUOM'), EditorComponentFactory::TYPE_FIELD, $hiddenfields);

            foreach ($hiddenfields as &$hiddenfield) {
                $hiddenfield->setProperty('hidden', true);
            }

            //Setting ISSYSTEM empty to make sure while duplicating record from system generated one should not be carrying ISSYSTEM = True.
            $obj['ISSYSTEM'] = '';
        }

        //dont show defaults till baseunit is set in edit mode?
        /*
        if ($this->state != Editor_ShowViewState && (!isset($obj['BASEUNIT']) || $obj['BASEUNIT'] == '')) {

            $hiddenFields = array(    'INVUOM',
                                      'POUOM',
                                      'OEUOM',
            );

            foreach ($hiddenFields as $hiddenField) {
                $view->findAndSetProperty(array('path' => $hiddenField), array('hidden' => true));
            }

        }
        */

        //on edit mode disable the units and grid for system UOM's such as Area
        if ($this->state == Editor_ShowEditState && $obj['ISSYSTEM'] == 'true') {
            $readonlyFields = array(    'NAME',
                                        'BASEUNIT',
                                        'ABBREVIATION',
                                        'UNIT',
                                        'CONVFACTOR',
            );

            foreach ($readonlyFields as $readonlyField) {
                $view->findAndSetProperty(array('path' => $readonlyField), array('readonly' => true));
            }

            $matches = array();
            $view->findComponents(array('path' => 'ENTRIES'), EditorComponentFactory::TYPE_GRID, $matches);
            if ( $matches ) {
                $matches[0]->setProperty('noNewRows', true);
                $matches[0]->setProperty('noDragDrop', true);
                $matches[0]->setProperty('hasFixedNumOfRows', true);
            }


        }

        //if system then dont show decimals column in the grid
        if ($obj['ISSYSTEM'] == 'true') {
            $view->findAndSetProperty(array('path' => 'NUMDECIMALS'), array('hidden' => true));
        }

        // Base unit is also a structure of the UOM group, its also an unit. so we put it as part of the unit entries.
        // However, on error, the page just caches the ui values and hence the base unit becomes part of the ENTRIES structure,
        // We have to remove it from the object structure in that case.
        if (is_array($obj['ENTRIES']) && count($obj['ENTRIES']) > 0) {
            foreach ($obj['ENTRIES'] as $indx => $entry)
            {
                if ($entry['ISBASE'] == 'true') {
                    unset($obj['ENTRIES'][$indx]);
                    break;
                }
            }

        }


        $key = Request::$r->_grpkey;

        $matches = array();
        $view->findComponents(array('path' => 'INVUOM'), EditorComponentFactory::TYPE_FIELD, $matches);
        if ($matches && $matches[0]) {
            $type = $matches[0]->getProperty('type');
            $type['restrict'] = array(
                array(
                    'pickField' => 'GRPKEY',
                    'operand' => '=',
                    'value' => $key
                )
            );
            $matches[0]->setProperty('type', $type);
        }

        $matches = array();
        $view->findComponents(array('path' => 'OEUOM'), EditorComponentFactory::TYPE_FIELD, $matches);
        if ($matches && $matches[0]) {
            $type = $matches[0]->getProperty('type');
            $type['restrict'] = array(
                array(
                    'pickField' => 'GRPKEY',
                    'operand' => '=',
                    'value' => $key
                )
            );
            $matches[0]->setProperty('type', $type);
        }

        $matches = array();
        $view->findComponents(array('path' => 'POUOM'), EditorComponentFactory::TYPE_FIELD, $matches);
        if ($matches && $matches[0]) {
            $type = $matches[0]->getProperty('type');
            $type['restrict'] = array(
                array(
                    'pickField' => 'GRPKEY',
                    'operand' => '=',
                    'value' => $key
                )
            );
            $matches[0]->setProperty('type', $type);
        }
        return true;
    }


    /**
     * Get the list of values ot pass over in the URLs
     *
     * @return array the url parameter to pass over
     */
    protected function GetSpecificURLParameters()
    {
        return array(
            '_grpkey',
        );
    }

    /**
     * @return string[]|null
     */
    protected function getEditorHiddenFields()
    {

        $extrafields['_grpkey'] = Request::$r->_grpkey;
        return $extrafields;
    }

    /**
     * Supporting Documents cannot be duplicated.
     *
     * @return bool
     */
    protected function canPrint()
    {
        return false;
    }

    /**
     * @return bool
     */
    protected function CanSaveAndNew()
    {
        return false;
    }

    /**
     * @param string[]      $_layout
     * @param array   $obj
     *
     * @return int
     */
    public function FigureOutNumOfRows($_layout, &$obj = null)
    {
        if ( $obj['ISSYSTEM'] == 'true') {
            if ($_layout['path'] == 'ENTRIES') {
                $_layout['hasFixedNumOfRows'] = true;
                $_layout['noDragDrop'] = true;
            }
        }
        return parent::FigureOutNumOfRows($_layout, $obj);

    }


    /**
     * @param string $entity
     * @param string $objId
     * @param string $doctype
     * @param string[] $fields  Not used
     *
     * @return array|false
     */
    public function getEntityData($entity, $objId, $doctype='', $fields=null)
    {
        $entityData = parent::getEntityData($entity, $objId);

        $newEntries = array();
        foreach ($entityData['ENTRIES'] as $key => $uomVal) {
            if ($uomVal['ISBASE'] && $uomVal['ISBASE'] == 'true') {
                $entityData['BASEUNIT'] = $uomVal['UNIT'];
                $entityData['ABBREVIATION'] = $uomVal['ABBREVIATION'];
            } else {
                $newEntries[] = $entityData['ENTRIES'][$key];
            }
        }

        $entityData['ENTRIES'] = $newEntries;

        return $entityData;
    }


}