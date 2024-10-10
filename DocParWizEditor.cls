<?
import('editor');

require_once "uperm.inc";        // The complex control...
/**
 * Class DocParWizEditor
 */
class DocParWizEditor extends Editor
{

    /**
     * @param array $params
     */
    function __construct($params)
    { 
        $helpIDs = array (
        'inv' => 'Transaction_Definition_Tabs_Basic_Redirect_IN',
        'po' => 'Transaction_Definitions_Tabs_Basic_Redirect_PO',
        'so' => 'Configuring_an_Order_Entry_Transaction_Definition',
        );
        $params['helpfile'] = $helpIDs[Request::$r->_mod];
        parent::__construct($params);
    }


    /**
     * @param   array    $_fields
     * @param   string   $_mode
     * @param   array    $_actualcols
     * @param   int      $line
     */
    function ShowMultiLineRow($_fields, $_mode, $_actualcols, $line = 0) 
    {
        $linecol = "#000000";
        for ($iV=0; $iV<$_fields['maxvertical']; $iV++) {
            $col = $iV % 2 ?
            '#CCCCCC' : '#DDDDDD';  ?>
        <TR>
        <?  $first = true;
         $totalcols = 0;
        foreach ($_fields['cells'] as $cell) {
            /** @noinspection OnlyWritesOnParameterInspection */
            $totalcols++;
            $vcell = $cell['_args'][$iV];

            if (!$vcell['hidden']) {

                $colwidth = $vcell['type']['multilinecolsepr'] ?:7;
                $defaultalign = 'left';
                $colalign = $vcell['type']['colalign'] ?:$defaultalign;
                $bgcol = $first ? $linecol : $col;
                $width = $first ? 1 : $colwidth;
            ?>
           <TD width="1" bgcolor="<? echo $bgcol; ?>" ><? echo Transparent($width, 1); ?></TD>
           <TD bgcolor="<? echo $col; ?>" valign="middle" align="<? echo $colalign; ?>" nowrap>

            <?    if ($vcell['_func'] == 'LineNo' && $_mode == 'inputs') { ?>
				<FONT size=1>&nbsp;<?  echo ($line+1);  ?></FONT>
				<?
     }
elseif ($vcell && $_mode == 'labels') {
                $this->ShowSimpleFieldLabel($vcell, true); 
     }
elseif ($vcell) {
    $this->ShowSimpleFieldValue($vcell); 
}
else {
                echo '&nbsp;'; 
}
                ?>
         </TD>
        <? 
        $first = false;
        
            }
        ?>
        <?    
        } ?>
     <TD width="0" bgcolor="<? echo $linecol; ?>"><? echo Transparent(1, 1); ?></TD>
		

     </TR>
        <? 
        } ?>
     <TR>
      <TD height="1" bgcolor="<? echo $linecol; ?>" colspan="<? echo
        count($_fields['cells']) * 2 + 1; ?>" ><? echo Transparent(1, 1); ?></TD>
     </TR>
        <?
    }


    /**
     * @param array $_params
     */
    function Editor_Instantiate(&$_params) 
    {
        eppp('Editor_Instantiate');

        global $gManagerFactory;

        $showInvTab = true;
        $showAPARTab = true;
        $showUserPermTab = true;
        $r             = Request::$r->_r;
        $mod         = Request::$r->_mod;

        $docparMgr    = $gManagerFactory->getManager($mod . 'documentparams');

        // global $_dbg; $_dbg = 1; eppp( $r );

        $docpar     = $docparMgr->get($r);
        $doctype    = $docpar['DOCID'];

        if ($doctype) {
            $tit = explode(':', $_params['title']);
            $_params['title'] = $tit[0] . ': ' . $doctype . ' Information';
        }
        
        switch ($doctype) {
        case 'Client Invoice':
            $_params['helpfile'] = 'Transaction_Definition_Tabs_Redirect';
            break;
        default :
            break;
        }

        $spi = $docpar['SALE_PUR_TRANS'];

        $affects_apar    = ($docpar['UPDATES_GL'] == 'true') ? true : false ;

        $affects_invgl = 0;

        if ( $docpar['UPDATES_INV'] != 'No') {
            if ((    $docpar['SALE_PUR_TRANS'] == 'Sale' && $affects_apar)  
                || $docpar['SALE_PUR_TRANS'] == 'Internal' 
            ) {
                $affects_invgl = 1;
            }
        }

        // It seems that MatchTemplates is required for multiline stuff.  Too bad.
        // It also seems that it has to be done before the call to parent::Editor_Instantiate

        $this->MatchTemplates($_params, array('path' => 'PRODLINE'), $fields);

        foreach ( $fields as $k => $field) {
            $fields[$k]['required'] = true;
        }

        $fields = array();


        $this->MatchTemplates($_params, array('path' => 'INVACCT'), $fields);
        foreach ( $fields as $k => $field) {
            $fields[$k]['required'] = 1;
        }
        $fields = array();


        $this->MatchTemplates($_params, array('path' => 'INVACCT2'), $fields);
        foreach ( $fields as $k => $field) {
            if ($spi == 'Purchase') {
                $fields[$k]['hidden'] = true;
            }
            else {
                $fields[$k]['required'] = 1;
            }
        }
        $fields = array();


        if ($mod == 'so' || $mod == 'po') {
            $this->MatchTemplates($_params, array('path' => 'CUSTVENDTYPE'), $fields);
            foreach ( $fields as $k => $field) {
                $fields[$k]['fullname'] = ($mod == 'so') ? 'Customer Type' : _('Vendor Type');
                $fields[$k]['desc'] = ($mod == 'so') ? 'Customer Type' : 'Vendor Type';
                $fields[$k]['type']['entity'] = ($mod == 'so') ? 'custtype' : 'vendtype';
                $fields[$k]['required'] = 1;
            }
        }
        
        $fields = array();


        $this->MatchTemplates($_params, array('path' => 'APARACCT'), $fields);
        foreach ( $fields as $k => $field) {
            if (!$affects_apar) {
                $fields[$k]['hidden'] = 1;
            } 
            else {
                $fields[$k]['fullname'] = ($mod == 'so' || $mod == 'tb') ? 'AR Account' : 'AP Account';
                $fields[$k]['desc'] = ($mod == 'so' || $mod == 'tb') ? 'AR Account' : 'AP Account';
            }
            $fields[$k]['required'] = 1;
        }
        $fields = array();
        $this->MatchTemplates($_params, array('path' => 'DOCPAR.SPECIAL_PRICELISTID'), $fields);
        $this->MatchTemplates($_params, array('path' => 'DOCPAR.UPDATES_PRICELISTID'), $fields);
        $this->MatchTemplates($_params, array('path' => 'DOCPAR.PRICELISTID'), $fields);
        foreach ( $fields as $k => $field) {
            $fields[$k]['type']['entity'] = $mod.'pricelist';
        }
        $fields = array();


        $this->MatchTemplates($_params, array('path' => 'SALESACCT'), $fields);
        foreach ( $fields as $k => $field) {
            if (!$affects_apar || $spi == 'Purchase') {
                $fields[$k]['hidden'] = 1;
            } 
            $fields[$k]['required'] = 1;
        }


        parent::Editor_Instantiate($_params);

        for($i=0;$i < count($_params['allfields']); $i++) {
            $path = $_params['allfields'][$i]['varpath'];

            switch($path) {
            case 'DOCPAR.USERPERM':
                {
                if ($mod == 'tb') {
                    $_params['allfields'][$i]['hidden'] = 1;
                } 
              break;
                }
            case 'DOCPAR.GLBATCH':
                {
                if ((!$affects_apar && !$affects_invgl) || $mod != 'tb') {
                    $_params['allfields'][$i]['hidden'] = 1;
                } 
              break;
                }
            case 'DOCPAR.GLJOURNAL':
                {
                if (!$affects_invgl || $mod != 'tb') {
                    $_params['allfields'][$i]['hidden'] = 1;
                }
              break;
                }
            case 'DOCPAR.DOCID':
                {
                $_params['allfields'][$i]['readonly'] = 1;
                $_params['allfields'][$i]['value'] = $doctype;
              break;
                }
            case 'DOCPAR.PRICELISTID':
            case 'DOCPAR.UPDATES_PRICELISTID':
            case 'DOCPAR.SPECIAL_PRICELISTID':
                {
                $_params['allfields'][$i]['hidden'] = 
                ($docpar['SALE_PUR_TRANS'] == 'Internal' || $docpar['SALE_PUR_TRANS'] == 'TimeBill') ? 1 : 0;
              break;
                }
            case 'INVACCT':
                {
                $_params['allfields'][$i]['hidden']        = ($affects_invgl && $spi != 'Purchase') ? 0 : 1;
                $_params['allfields'][$i]['required']    = 1;
              break;
                }
            case 'INVACCT2':
                {
                $label = 'Inventory Offset Account';
                $_params['allfields'][$i]['hidden']     = ($affects_invgl) ? 0 : 1;
                $_params['allfields'][$i]['fullname']     = $label;
                $_params['allfields'][$i]['desc']         = $label;
                $_params['allfields'][$i]['required']     = ($affects_invgl) ? 1 : 0;
              break;
                }
            case 'APARACCT':
                {
                if (!$affects_apar) {
                    $_params['allfields'][$i]['hidden'] = 1;
                } 
                else {
                    $_params['allfields'][$i]['required'] = true;
                    $_params['allfields'][$i]['fullname'] = ($mod == 'so' || $mod == 'tb') ? 'AR Account' : 'AP Account';
                    $_params['allfields'][$i]['desc'] = ($mod == 'so' || $mod == 'tb') ? 'AR Account' : 'AP Account';
                }
              break;
                }
            case 'SALESACCT':
                {
                if ($spi == 'Purchase') {
                    $_params['allfields'][$i]['fullname']     = 'Inventory Account';
                    $_params['allfields'][$i]['desc']         = 'Inventory Account';
                }
                $_params['allfields'][$i]['hidden'] = (!$affects_apar ) ? 1 : 0;
                $_params['allfields'][$i]['required'] = 1;
              break;
                }
            case 'DOCPAR.TERM_NAME':
                {
                $_params['allfields'][$i]['type']['entity'] = (($mod == 'so' || $mod == 'tb') ? 'ar' : 'ap') . 'term';
                if ($mod == 'inv') {
                    $_params['allfields'][$i]['hidden'] = 1;
                }
              break;
                }
            default:
                { 
                } // nop
            }
        }


        if ($affects_apar || $affects_invgl) {
            if (!$affects_invgl || ( $affects_invgl )) {
                $showInvTab = true;
            }
            if ( $mod == 'inv' || ($mod == 'po') ||  ($mod == 'so') ) {
                $showAPARTab = false;
            }
        }
        else {
            $showInvTab = false;
            $showAPARTab = false;
        }


        if ($mod == 'tb') {
            $showUserPermTab = false;
            $showAPARTab = false;
            $showInvTab = false;
            $showTBTab = true;
        } else {
            $showTBTab = false;
        }

        $newpages = array();
        foreach ($_params['layout']['pages'] as $page) {
            if (strcmp($page['fields'][0]['path'], 'GLINFO_INV') == 0 && !$showInvTab  
                || strcmp($page['fields'][0]['path'], 'GLINFO_OE') == 0 && !$showAPARTab 
                || strcmp($page['fields'][0]['path'], 'GLINFO_TB') == 0 && !$showTBTab 
                || strcmp($page['fields'][0]['path'], 'DOCPAR.DOCPAR_USERS') == 0 && !$showUserPermTab 
            ) {
            }
            else {
                $newpages[] = $page;
            }
        }
        $_params['layout']['pages'] = $newpages;

    }

    /**
     * Function to show hideen fields.
     */
    function ShowHiddenFields() 
    {

        Editor::ShowHiddenFields();
        ?><INPUT type="hidden" name="_r" value="<?echo(Request::$r->_r)?>"><?

        upermDrawHiddenVarsForMainLayer();

    }

    /**
     * Draw the special control
     *
     * @param array $_params
     */
    function ShowFields($_params) 
    {

        $fields = $_params['fields'];
        $field = $fields[0];        

        // print $field['path'] . "<BR>\n";
        // global $_dbg; $_dbg=1; eppp( $fields ); exit;

        if ( $field['path'] == 'DOCPAR.DOCPAR_USERS' ) {

            $path = Request::$r->_obj__DOCPAR__DOCID;

            $form = $field['form'];

            print "<BR>&nbsp;&nbsp;Setting Permissions for: <B>$path</B>";

            upermDrawComplexControl($form, $path, "_obj__DOCPAR__DOCID");

            return;
        }

        Editor::ShowFields($_params);        
    }

    /**
     * @param array $_params
     */
    function ProcessSaveAction(&$_params) 
    {
        upermProcessSaveAction("_obj__DOCPAR__DOCID");
        Editor::ProcessSaveAction($_params);        
    }

    /**
     * @param array $_params
     * @return  bool
     */
    function ProcessCreateAction(&$_params) 
    {
        upermProcessSaveAction("_obj__DOCPAR__DOCID");
        Editor::ProcessCreateAction($_params);
        return true;
    }

}