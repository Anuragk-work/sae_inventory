<?php
require_once 'scm_util.inc';

/**
 * Class ItemLister
 */
class ItemLister extends NLister
{

    function __construct()
    {
        $helpIDs = array ('inv' => 'Viewing_and_Managing_the_Items_List', 'po' => 'Viewing_and_Managing_the_Items_List', 'so' => 'Viewing_and_Managing_the_Items_List', 'pa' => 'Viewing_and_Managing_the_Items_List' );
        
        if(IsAdvancedConfiguration()) {
            $fields = array('ITEMID','NAME','PRODUCTLINEID','GLGROUP','ITEMTYPE', 'STATUS');
        } else {
            $fields = array('ITEMID','NAME','PRODUCTLINEID','ITEMTYPE', 'STATUS');
        }

        $unhiddenFields = CNSetupManager::getUnhiddenFieldsForContractsInItem();

        parent::__construct(
            array (
                'entity'            => 'item',
                'fields'            => $fields,
                'importtype'        => 'item',
                // the list of fields which need special encoding
                'nonencodedfields'  => array( 'ITEMID', 'RECORD_URL' ),
                'unhiddenFields'    => $unhiddenFields,
                'helpfile'          => $helpIDs[Request::$r->_mod],
                'enablemultidelete' => true,
                // TODO: Temporary workaround for prod escalation: permanently showing inactive; fix me for real
                // 'showstatus'        => 1,
            )
        );
    }


    /**
     * @return array
     */
    function CalcFiltersLite() 
    {
        global $kINVid;

        $filters = parent::CalcFiltersLite();
        $mod    = Request::$r->_mod;
        
        //$itemMgr = $gManagerFactory->GetManager('item');
        //$allowKit = $itemMgr->Enablekitting();
        //$allowLightAssembly = $itemMgr->EnableLightAssembly();
        
        GetModulePreferences($kINVid, $prefs);

        /* From dimension structure we don't want to restrict it by module's itemtype */
        if (!Request::$r->_fromGLAcctGrp) {
            if ($mod == 'so') {
                $filters[] = array('item.itemtype', '<>', 'NP');
            } elseif ($mod == 'po') {
                $filters[] = array('item.itemtype', '<>', 'NS');
            }
        }

        if (!IsKitEnabled()) {
            $filters[] = array('item.itemtype', '<>', 'K' );
        }

        if ($prefs['LIGHTASSEMBLY'] != 'T') {
            $filters[] = array('item.itemtype', '<>', 'SK' );
        }

        return $filters;
    }


    /**
     * @param string    $msg
     * @param string    $image
     * @param string    $url
     * @param string    $done
     */
    function getTopPanelMessage(&$msg,&$image, &$url,/** @noinspection PhpUnusedParameterInspection */ &$done) 
    {
        $hlpPath = GetLocalizedHelpUrl();
                
        //$url  = "lister.phtml?.op=".GetOperationId('gl/lists/recurglbatch');
        $url=$hlpPath.'XX_NF/NewStockableKitCostingMethod.htm';
        
        //$image=$hlpPath.'Resources/Images/ItemInfoFIFOdrop-down2.png';
        $image='../resources/images/ia-app/icons/help.gif';
        
        //$done = "lister.phtml?.sess=$_sess&.op=$_op";
        
        //$msg='Changes Coming Soon To Display Of Stockable Kit Costing Method. Click To Read More.';
        $msg='';
    }

    /**
     * @return string
     */
    function genTopPanel() 
    {
        
        $this->getTopPanelMessage($msg, $image, $url, $done);
        
        if ((isset($msg) && $msg!="")&&(isset($url) && $url!="")) {
            ?>
         <div style="width:100%;">
          <center>
           <a href="<?echo(FwdUrl($url, $done));?>" target="_blank">
         <img src="<?echo($image);?>" alt="" border="0">
         <font face="Verdana, Arial, Helvetica" size="1">
        <?echo($msg);?>
         </font>
        </a>
       </center>
         </div>
            <?
        }
        return parent::genTopPanel();
    }

    /**
     * @return array
     */
    function BuildQuerySpec()
    {
        $querySpec = parent::BuildQuerySpec();
        $gManagerFactory = Globals::$g->gManagerFactory;            
        
        $dimComp = Request::$r->_dimComp; 
        if ( isset($dimComp) && $dimComp!='' ) {
            if($this->showPrivate ) {
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
        if ( isset($grpId) && $grpId!='' && $grpId!='None' ) {            
            if($this->showPrivate ) {
                SetReportViewContext();
            }
            $groupMgr = $gManagerFactory->getManager('itemgroup');
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
        $ret .= "<g name='.fromGLAcctGrp'>" . isl_htmlspecialchars(Request::$r->_fromGLAcctGrp) . "</g>";
        return $ret;
    }

    /**
     * @return string
     */
    protected function getMoreTags()
    {
        $gManagerFactory = Globals::$g->gManagerFactory; 
        $grpMgr = $gManagerFactory->getManager('itemgroup');
        
        $params = array(
            'selects' => array('ID'),
            'orders' => array(array('ID')),
        );
        
        $lists = $grpMgr->GetList($params);
        $grps = array('None');
        foreach($lists as $grp) {
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
