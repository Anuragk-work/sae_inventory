<?
//===========================================================================
//	FILE: ProductLineManager.cls
//	AUTHOR: John P. Campbell
//	DESCRIPTION:
//
//	(C) 2000, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	Corporation and is protected by the copyright laws.  Information
//	herein may not be used, copied or disclosed in whole or in part
//	without prior written consent from Intacct Corporation.
//===========================================================================

/**
 * Class ProductLineManager
 */
class ProductLineManager extends HierarchicalEntityManager
{
    /**
     * @param array $values
     *
     * @return bool
     */
    function _PrepValues(&$values)
    {
        global $gErr, $kSOid, $kPOid, $kINVid;

        $mod = Request::$r->_mod;

        $modMap = array(
        'so'  => $kSOid,
        'po'  => $kPOid,
        'inv' => $kINVid,
        );
        $values['MODULEKEY'] = $modMap[$mod];

        $ok = $this->CheckForLoop($values['PRODUCTLINEID'], $values['PARENTLINE']);

        if (!$ok) {
            $msg = "Parent cannot refer to self or any child product line.";
            $gErr->addIAError('INV-0774', __FILE__ . ':' . __LINE__, $msg, []);
        }

        $ok = $ok && $this->prepParentProductline($values);

        //if (isset($values['PARENTLINE']) && strcmp($values['PARENTLINE'],$values['PRODUCTLINEID']) == 0) {
        //	$ok = false;
        //	$msg = _("Parent cannot refer to self.");
        //	$gErr->addIAError('INV-0775',__FILE__.':'.__LINE__,$msg, []);
        //}
        return $ok;
    }

    /**
     * @param array $root
     * @param array $newParent
     *
     * @return bool
     */
    function CheckForLoop($root,$newParent) 
    {
        $qry = 'QRY_PRODUCTLINE_CHECK_LOOPS';
        $args = array ($this->_cny, $newParent, $this->_cny, $root, $this->_cny);

        $res = $this->DoQuery($qry, $args);

        if (Util::countOrZero($res) > 0) {
            return false;
        }

        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularAdd(&$values)
    {
        $source = 'ProductLineManager::Add';

        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->_PrepValues($values);
        $ok = $ok && parent::regularAdd($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $gErr = Globals::$g->gErr;
            $msg = "Could not add Product Line record!";
            $gErr->addIAError('INV-0776', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }

        return $ok ;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function prepParentProductline(&$values)
    {
        if ( ! empty($values['PARENTLINE']) ) {
            $filter = [
                'selects' => [ 'RECORDNO' ],
                'filters' => [
                    [
                        [ 'PRODUCTLINEID', '=', $values['PARENTLINE'] ],
                    ],
                ],
            ];
            $result = $this->GetList($filter);

            if ( isset($result[0]) && ! empty($result[0]['RECORDNO']) ) {
                $values[':parentkey'] = $result[0]['RECORDNO'];
            }
        }

        return true;
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    protected function regularSet(&$values)
    {
        $source = 'ProductLineManager::Set';

        $ok = $this->_QM->beginTrx($source);
        $ok = $ok && $this->_PrepValues($values);
        $ok = $ok && parent::regularSet($values);

        $ok = $ok && $this->_QM->commitTrx($source);
        if (!$ok) {
            $gErr = Globals::$g->gErr;
            $msg = "Could not set Product Line record!";
            $gErr->addIAError('INV-0777', __FILE__ . ':' . __LINE__, $msg, []);
            epp("$source: Error: $msg");
            $this->_QM->rollbackTrx($source);
        }
        
        return $ok;
    }


    /**
     * @param string $pline
     *
     * @return bool
     */
    function FindGLGroupAncestor($pline) 
    {
        $gErr = Globals::$g->gErr;
                $source = 'ProductLineManager::FindGLGroupAncestor';
        if ($pline == '') { 
            return false; 
        }
        
        global $gManagerFactory;        
        $grpMgr =  $gManagerFactory->getManager('itemglgroup');

        // 1 - get all ancestors of $pline (inclusive)
        $familyTree = $this->GetAncestors($pline);

        if (!$familyTree) {
                        $msg = "Invalid Product Line Provided!";
                        $gErr->addIAError('INV-0778', __FILE__ . ':' . __LINE__, $msg, []);
                        epp("$source: Error: $msg");
            return false;
        }

        // if we don't find one, then just return this one
        $ancestorLine = $pline;

        foreach($familyTree as $line) {
            // is line in docpargl
            if ($this->CheckLineIDinDocParGL($line['PRODUCTLINEID'])) {
                $ancestorLine = $line['PRODUCTLINEID'];
                break;
            }
        }

        $raw = $grpMgr->GetRaw($ancestorLine);
    
        return $raw[0] ?? false;
    }


    /**
     * @param string $pline
     *
     * @return bool|string[][]
     */
    function GetAncestors($pline) 
    {
        $qry        = 'QRY_PRODUCTLINE_GETANCESTORS';
        $args        = array ($this->_cny,$this->_cny,$pline,$this->_cny);
        return $this->DoQuery($qry, $args);
    }

    /**
     * @param   string $pline
     * @param   string $fmt
     *
     * @return bool|string[][]
     */
    function GetChildren($pline,$fmt='array') 
    {
        $qry        = 'QRY_PRODUCTLINE_GETCHILDREN';
        $args        = array ($this->_cny,$this->_cny,$pline,$this->_cny);
        $children    = $this->DoQuery($qry, $args);
        if ($fmt == 'array') {
            return $children;
        }
        elseif($fmt == 'tree') {
            foreach($children as $line) {
                $node = array (
                'PARENT'    => $line['PARENTLINEID'],
                'ID'        => $line['PRODUCTLINEID'],
                );
                $ok = $this->_TreeMgr->InsertNode($node);
                if (!$ok) {
                    return false;
                }
            }
            return $this->_TreeMgr->GetTree();
        }
        return false;
    }

    /**
     * @param string $pline
     *
     * @return bool|string[][]
     */
    function UpdateGLGroupsOnParentChange($pline) 
    {
                
        $nextGrp = $this->FindGLGroupAncestor($pline);

        // the root node is in docpargl, so leave things as they are
        if (strcmp($nextGrp['NAME'], $pline) == 0) {
            return true;
        }

        // get the decendants as a Tree
        $children = $this->GetChildren($pline, 'tree');
        return $this->UpdateItemsForChildren($children, $nextGrp['RECORD#']);
    }

    /**
     * @param string $ID
     *
     * @return bool
     */
    function CheckLineIDinDocParGL($ID) 
    {
        $qry = 'QRY_PRODUCTLINE_CHECK_DOCPARGL' ;
        $args = array ( $ID );

        $ret = $this->DoQuery($qry, $args);
        if (isset($ret[0])) {
            return true;
        }
        else {
            return false;
        }

    }

    /**
     * @param array  $tree
     * @param string $nextGrpKey
     *
     * @return bool|string[][]
     */
    function UpdateItemsForChildren($tree,$nextGrpKey) 
    {
        
        if (count($tree) == 0) { 
            return true; 
        }
        
        global $gQueryMgr;
        
        // 1 - Check if root in docpargl
        $rootID = $tree['ID'];
        if ($this->CheckLineIDinDocParGL($rootID) ) {
            return true;
        }
        

        $myqry['QRY_UPDATE_ITEM_GLGROUP_SPCL'] = array (
        'QUERY'     => "UPDATE icitem SET glgrpkey = $nextGrpKey WHERE productlinekey = ? and cny# = ?",
        'ARGTYPES'    => array ('text','integer')
        );
        $gQueryMgr->LoadQueries($myqry);
        $args = array ( $rootID, $this->_cny );
        $ok = $this->DoQuery('QRY_UPDATE_ITEM_GLGROUP_SPCL', $args);

        // recurse down the tree
        foreach ($tree as $node) {
            $ok = $ok && $this->UpdateItemsForChildren($node['CHILDREN'], $nextGrpKey);
        }
        return $ok;
    }


    /**
     * Overridden to to API specific validation
     *
     * @param array $values
     *
     * @return bool
     */
    public function API_Set(&$values)
    {
        // Check if API is intentionally trying to change the PRODUCTLINEID of an employee
        $ok           = true;
        $gErr         = Globals::$g->gErr;
        $prodLineData = $this->API_Get($values['RECORDNO']);

        if ( $prodLineData !== false && is_array($prodLineData) ) {
            if ( $prodLineData[0]['PRODUCTLINEID'] != $values['PRODUCTLINEID'] ) {
                $gErr->addIAError('INV-0213', __FILE__ . ':' . __LINE__, "You can not change the PRODUCTLINEID.", []);
                $ok = false;
            }
        }

        return $ok && parent::API_Set($values);
    }
}
