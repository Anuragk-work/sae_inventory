<?php
//
//================================================================================
//	FILE:			RecurDocumentEntryManager.cls
//	AUTHOR:			bharris
//	DESCRIPTION:	Manager class for Recurdocumententry object.
//
//	(C)2000-2008, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//

import('DocumentEntryManager');

/**
 * Class RecurDocumentEntryManager
 */
class RecurDocumentEntryManager extends DocumentEntryManager
{
    /**
     * @param string $_schema
     *
     * @return bool|null|string
     */
    function GetHomeModule($_schema = '')
    {
        $mod = Request::$r->_mod;
        if ( isset($mod) && $mod != '' && in_array($mod, array('so', 'po', 'inv')) ) {
            return $mod;
        }

        return $this->_schemas[$this->_entity]['module'] ?? false;
    }



    /**
     * Adds the line item to the database.
     * This was added to provide Mega checking.
     *
     * @param  array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values) 
    {
        $source = "RecurDocumentEntryManager::Add";
        
        $ok         = $this->_QM->beginTrx($source);
        $ismega     = IsMultiEntityCompany();
        if($ismega) {
            $ok     = $ok && $this->PrepDefaultValues($values);
        }

        // Update the status based on the line status
        if ($values['LINESTATUS'] != 'Active') {
            $values['STATUS'] = 'inactive';
        }

        // clear the WHENMODIFIEID field coming from DOCUMENTENTRY in convert by line case
        unset($values['WHENMODIFIED']);

        $ok = $ok && OwnedObjectManager::regularAdd($values);
        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }


    /**
     * @param string $_parent
     *
     * @return array|false
     */
    function GetByParent($_parent) 
    {
        global $gManagerFactory;

        $mod = Request::$r->_mod;

        $docMgr = $gManagerFactory->getManager('recurdocument');
        $docIDRes = $docMgr->DoQuery('QRY_RECURDOCUMENT_GET_DOCPARID_FOR_THIS_RECURDOC', array($_parent));

        $this->_docType = $docIDRes[0]['DOCID'];

        $doc = $mod.'documententry';
        $hasCustomFields = $this->HasCustomFields($doc, $this->_docType);

        if($hasCustomFields) {
            $this->_entity = $mod.'documententry';

            $this->LoadFields();

            $this->_entity = 'recurdocumententry';

            $this->MergeTableInfo();  // add schema information to $kTables

            $this->MergeObjectSchema();  // build the paths

            // MERGE kSchemas['object']
            $this->MergeObjectFieldList(); // add the custom fields to the object field list.
            
        }
    
        return parent::GetByParent($_parent);
    }

    /**
     * @param string $entity
     * @param string $doctype
     *
     * @return bool
     */
    function HasCustomFields($entity, $doctype)
    {
        $retVal = false;

        // Custom fields require document type for this object
        if (isset($doctype) && $doctype !== '') {
            // This is kind of a hack. We prevent calling HasCustomFields by checking the doctype, but actually the problem is that the $entity passed in is
            // invalid ("codocumententry") because of the global module concatenation. The correct thing to do is to have so, po, inv recurdocumententry.
            // The whole thing with the global module is a hack.  We may need to set the global module in the XyzRecurDocument(Entry)Manager constructor just
            // like we do in XyzDocument(Entry)Manager. We are doing this temporarily just so we can continue "supporting" recurdocumententry as standard
            // object (as defined in Util_StandardObjectMap)
            $retVal = parent::HasCustomFields($entity, $doctype);

        }
        return $retVal;
    }

    /**
     * @param int  $cny Company cny#
     * @param bool $withLookup
     */
    function LoadCustomFields($cny = 0, /** @noinspection PhpUnusedParameterInspection */ $withLookup = true)
    {
        import('RecurDocumentManager.cls');

        if( ! $this->_docType ) {
            $this->_docType = Request::$r->_dt;
        }
        $mod = Request::$r->_mod;
        $doc = $mod.'documententry';

        $hasCustomFields = $this->HasCustomFields($doc, $this->_docType);

        if($hasCustomFields) {
            $this->_entity = $mod.'documententry';
            $this->_schemas[$this->_entity]['parententity'] = $mod.'document';

            parent::LoadCustomFields($cny, false);
            $this->_entity = 'recurdocumententry';
        }
    }
    
    /**
     * No macro fields for recurring 
     */
    public function LoadMacroFields()
    {
            
    }

    /**
     * @return bool
     */
    function ExistCustomFields() 
    {
        $this->_docType = Request::$r->_dt;
        $mod = Request::$r->_mod;
        $doc = $mod.'documententry';

        $headerMgr = Globals::$g->gManagerFactory->getManager(
            'recurdocument',
            false,
            ['DOCTYPE' => $this->_docType]
        );

        $hasCustomFields = $this->HasCustomFields($doc, $this->_docType);

        if(!$hasCustomFields) {
            return $headerMgr->HasCustomFields($doc, $this->_docType);
        }

        $this->_entity = $mod.'documententry';
        $this->_schemas[$this->_entity]['parententity'] = $mod.'document';


        return $this->HasCustomFields($this->_entity, $this->_docType);
    }

    /**
     * NOTE: Because of the (unusual) relationship between DocumentEntryManager and RecurDocumentEntryManager
     *   classes this function must be called by the DocumentEntryManager statically. It would be better to
     *   re-architect RecurDocumentEntryManager to not be a sub-class of DocumentManager (maybe a composition?).
     *
     * Remove any custom fields. Purge only for records belonging to this document type
     *
     * @param  string $column  the column that needs to be purged.
     * @param  string $docType the type of document (Sales Order, etc.)
     * @param  array  $values  list of values that should be purged
     *
     * @return bool
     */
    public static function PurgeCustomFieldColumn_static($column, $docType, $values = null)
    {
        $qry = "
			update recurdocentrymst set $column = null where cny# = :1 and record# in (
				select e.record# from recurdocentrymst e, recurdochdrmst d, docpar p where
				e.recurdochdrkey = d.record# and d.docparkey = p.record# and p.docid = :2
				and e.cny# = :1 and d.cny# = :1 and p.cny# = :1
			) and ";
        $qry = array($qry, GetMyCompany(), $docType);
        if ( ! $values ) {
            $qry[0] .= "$column is not null";
        } else {
            $qry = PrepINClauseStmt($qry, $values, " $column ");
        }
           return ExecStmt($qry);
    }

    /**
     * MergeTableInfo
     */
    function MergeTableInfo() 
    {

        $this->_docType = Request::$r->_dt;
        $mod = Request::$r->_mod;

        $doc = $mod.'documententry';
        $hasCustomFields = $this->HasCustomFields($doc, $this->_docType);

        if(!$hasCustomFields) {
            parent::MergeTableInfo();
        }

        $this->_entity = 'recurdocumententry';

        $this->_schemas[$this->_entity]['parententity'] = 'recurdocument';
        parent::MergeTableInfo();
    }

    /**
     * Formats the location key on line items prior to database adds.
     * This was added to provide Mega checking.
     *
     * @param  array $values
     *
     * @return bool
     */
    function PrepDefaultValues(&$values) 
    {
        global $gManagerFactory, $gErr;

        $ok = true;
        //splitting Itemid-name and passing only itemid
        $itemid = explode('--', $values['ITEMID']);
        $values['ITEMID']=$itemid[0] ;

        //splitting warehouseid-name and passing warehouseid
        $warehouseid = explode('--', $values['WAREHOUSE']['LOCATION_NO']);
        $values['WAREHOUSE']['LOCATION_NO'] = $warehouseid[0];

        if( $values['LOCATION'] ) {
            list($values['LOCATION'])     = explode('--', $values['LOCATION']);
            $locManager                 = $gManagerFactory->getManager('location');
            $arrExplode = explode('--', $values['LOCATION']);
            $loc                         = array_shift($arrExplode);
            $row                         = $locManager->GetRaw($loc);
            $values[':locationkey']     = $row[0]['RECORD#'];
        }
        else{
            if( IsMultiEntityCompany()) {
                // Check for entity context
                if (!GetContextLocation() ) {
                    $gErr->addIAError('INV-0781', __FILE__ . '.' . __LINE__, "Empty location is invalid; A valid Multi-Entity location must be specified", []);
                    $ok = false;
                }
                else {
                    $values[':locationkey'] = GetContextLocation();
                }
                
            }
        }
        return $ok;
    }

    /**
     * @param int $cny
     * @param string $entity
     * @param string $module
     * @param bool   $followgldimensions
     * @param array   $ignoreList
     *
     * @return array|bool
     */
    public static function LoadDimensionFields($cny, $entity, $module, $followgldimensions, $ignoreList)
    {
        // We do not want the behavior of this function in DocumentEntryManager, so we are accessing the "Default" behavior.
        return parent::DefaultLoadDimensionFields($cny, $entity, $module, $followgldimensions, $ignoreList);
    }

    /**
     * The default behavior for DocumentEntryManager is to use TASKKEY instead of TASKDIMKEY.  However, RecurDocumentEntry uses TASKDIMKEY.
     *
     * @return bool
     */
    protected function ShouldUseTASKKEY()
    {
        return false;
    }

    /**
     * @param array $values
     * @return bool
     * @throws Exception
     */
    function TranslateRecord(&$values)
    {
        $parentReturn = parent::TranslateRecord($values);

        // RecurDocumentEntry uses TASKDIMKEY instead of TASKKEY (in DocumentEntry)
        if (!isset($values['TASKDIMKEY'])) {
            $values['TASKDIMKEY'] = $values['TASKKEY'];
        }

        return $parentReturn;
    }
}
