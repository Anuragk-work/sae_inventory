<?php
/**
*    FILE: SupportingDocumentsLister.cls
*    AUTHOR: John Donagher
*    DESCRIPTION: 
*
*    (C) 2000, Intacct Corporation, All Rights Reserved
*
*    This document contains trade secret data that belongs to Intacct
*    Corporation and is protected by the copyright laws.  Information
*    herein may not be used, copied or disclosed in whole or in part
*    without prior written consent from Intacct Corporation.
*/


import('NLister');

class DocHistoryLister extends NLister
{

    public function __construct()
    {
        $r = Request::$r->_r;

        /** @noinspection PhpUndefinedVariableInspection */
        parent::__construct(
            array(
            'entity'        => 'dochistory',
            'title'         => ['id'=> 'IA.TRANSACTION_HISTORY_FOR_TRANSACTION_NAME', 'placeHolders'=>[['name'=> 'TRANSACTION_NAME' ,'value'=>$r]]],
            'fields'        => array(
                                    'DOCUMENTCREATED',
                                    'DOCUMENTID',
                                    'SOURCEDOCUMENTID',
                                    'DOCSTATE',
            ),
            'disableedit'    => true,
            'disabledelete'    => true,
            'helpfile'        => $helpfile
            )
        );
    }

    /**
     * @return DocHistoryManager
     */
    public function getEntityMgr()
    {
        assert($this->entityMgr instanceof DocHistoryManager);
        return $this->entityMgr;
    }

    /**
     * @return array
     */
    public function BuildQuerySpec()
    {
        $r = Request::$r->_r;
        $docHistory = $this->getEntityMgr()->getByParent($r); // history per transaction is always 1 record
        $querySpec = parent::BuildQuerySpec();
        $querySpec['filters'][0][] = array('BASEDOCKEY','=',$docHistory[0]['BASEDOCKEY']);
        return $querySpec;
    }

    /**
     * @return string
     */
    public function genGlobs()
    {
        $r = Request::$r->_r;
        $ret = parent::genGlobs();
        $ret .= "<g name='.r'>" . $r. "</g>";
        return $ret;
    }
}
