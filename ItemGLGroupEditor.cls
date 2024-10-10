<?php
/**
 * =============================================================================
 *
 * FILE:        ItemGLGroupEditor.cls
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
 * Class ItemGLGroupEditor
 */
class ItemGLGroupEditor extends FormEditor
{

    /**
     * @param array $_params
     */
    public function __construct($_params = array())
    { 
        parent::__construct($_params); 
    }

    /**
     * @param array $obj
     *
     * @return bool
     */
    protected function mediateDataAndMetadata(&$obj)
    {
        import('DocumentParamsManager');
        $tdhasrevrec = DocumentParamsManager::TDHasEnableRevRec();

        $view = $this->getView();

        if (!$tdhasrevrec) {
            $viewonlyfields = array('DEFERREDREVACCTKEY','DEFAULTREVRECTEMPLKEY');
            foreach ($viewonlyfields as $path) {
                $matches = array();
                $view->findComponents(array('path' => $path), EditorComponentFactory::TYPE_FIELD, $matches);
                if ($matches) {
                    $matches[0]->setProperty('hidden',  true);
                }
            }
        }

        return true;
    }
}
