<?

/**
 * Class WarehouseLister
 */
class WarehouseLister extends NLister
{
    function __construct()
    {
        $helpIDs = array (
        'inv' => 'Viewing_and_Managing_the_Warehouse_List',
        'po' => 'Viewing_and_Managing_the_Warehouse_List',
        'so' => 'Viewing_and_Managing_the_Warehouse_List',
        );
        $helpfile = $helpIDs[Request::$r->_mod];
        parent::__construct(
            array(
            'entity'        =>  'warehouse',
            'fields'        =>  array('WAREHOUSEID', 'SHIPTO.CONTACTNAME', 'NAME'),
            'importtype'    =>  'warehouse',
            'nonencodedfields' => array('RECORD_URL','WAREHOUSEID', 'LOC.RECORD_URL', 'SHIPTO.RECORD_URL'),
            'helpfile'        => $helpfile
            )
        );
    }

    /**
     * @return array
     */
    function BuildQuerySpec()
    {
        $querySpec = parent::BuildQuerySpec();
        $gManagerFactory = Globals::$g->gManagerFactory;

        $dimComp = Request::$r->_dimComp;
        if ( isset($dimComp) && $dimComp != '' ) {
            if ( $this->showPrivate ) {
                SetReportViewContext();
            }
            $dimCompMgr = $gManagerFactory->getManager('glacctgrp');
            $members = $dimCompMgr->getDimensionMembers($dimComp);
            if ( !count($members) ) {
                $members = array('9999999');
            }
            $querySpec['filters'][0][] = array('RECORDNO', 'IN', $members);
        }

        // when it comes from group
        $grpId = Request::$r->_groupid;
        if ( isset($grpId) && $grpId != '' && $grpId != 'None' ) {
            if ( $this->showPrivate ) {
                SetReportViewContext();
            }
            $groupMgr = $gManagerFactory->getManager('warehousegroup');
            $members = $groupMgr->getGroupMembersById($grpId, false);

            $querySpec['filters'][0][] = array('RECORDNO', 'IN', $members['MEMBERRECS']);
        }

        return $querySpec;
    }

    /**
     * @return string
     */
    function genGlobs()
    {
        $ret = parent::genGlobs();
        $ret .= "<g name='.groupid'>" . isl_htmlspecialchars($this->_params['groupid']) . "</g>";
        $ret .= "<g name='.dimComp'>" . isl_htmlspecialchars(Request::$r->_dimComp) . "</g>";
        return $ret;
    }

    /**
     * @return string
     */
    protected function getMoreTags()
    {
        $gManagerFactory = Globals::$g->gManagerFactory;
        $grpMgr = $gManagerFactory->getManager('warehousegroup');

        $params = array(
            'selects' => array('ID'),
            'orders' => array(array('ID')),
        );

        $lists = $grpMgr->GetList($params);
        $grps = array('None');
        foreach ( $lists as $grp ) {
            $grps[] = $grp['ID'];
        }

        $groupsMenu = implode('~~', $grps);
        $grpid = $this->_params['groupid'] ?: 'None';

        $tags = "<groupsMenu>$groupsMenu</groupsMenu>\n
                <grpid>$grpid</grpid>\n";

        return $tags;
    }

    /**
     * @param array $_params
     *
     * @return array
     */
    function CalcParams($_params)
    {
        $_params = parent::CalcParams($_params);
        $_params['groupid'] = Request::$r->_groupid;

        return $_params;
    }


}


