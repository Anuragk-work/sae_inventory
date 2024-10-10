<?
import('Editor');

/**
 * Class PreDocEditor
 */
class PreDocEditor extends Editor
{
    /**
     * @param array $_params
     */
    function __construct($_params)
    { 
        $helpIDs = array ( 'inv' => 'Create_Inventory_Transaction_Redirect', 'so' => 'Order_Entry_Transaction_Tabs_Redirect', 'po' => 'Purchasing_Transaction_Tabs_Redirect' ) ;
        $_params['helpfile'] = $helpIDs[Request::$r->_mod];
        parent::__construct($_params);
    }

    /**
     * @param array $_params
     *
     * @return bool
     */
    function ProcessCreateAction(&$_params) 
    {
        global $gManagerFactory;
        $entityMgr = $gManagerFactory->getManager('predoc');
        $obj =& Request::$r->GetCurrentObject();
        $ok = $entityMgr->add($obj);
        $entityDesc = $_params['entityDesc'];

        if (!$ok) { 
            global $gErr;
            $gErr->addIAError(
                'INV-0762', __FILE__.":".__LINE__,
                "Updating $entityDesc failed",
                ['ENTITY_DESC' => $entityDesc]
            );
            $this->state = $this->kErrorState;
        }
        Request::$r->_currentlayer = 2;

        return $ok;
    }


    /**
     * @param array $_params
     *
     * @return array
     */
    function Buttons_Instantiate($_params) 
    {
        //global $gSecurity;
        //$dobutton = 'Continue';
        //$doaction = 'create';
        // 	//$cancelbutton = 'Cancel';
        //$deliverbutton = 'Deliver';
        //$deliveraction = 'deliver';

        //$_params['dobutton'] = $dobutton;
        //$_params['doaction'] = $doaction;
        //$_params['cancelbutton'] = $cancelbutton;
        return $_params;
    }

    /**
     * @param array $_params
     *
     * @return array
     */
    function Editor_Expand($_params)
    {
        global $gManagerFactory;
        $entityMgr = $gManagerFactory->getManager($_params['entity']);

        $mod = Request::$r->_mod;

        if ($mod) { 
            $entityMgr->SetHomeModule($mod);
        }

        $dt = Request::$r->_dt;

        if ($dt) {
            $_params['title'] = $dt;
        }

        return Editor::Editor_Expand($_params);
    }

    /**
     * @param array $_params
     *
     */
    function Editor_Instantiate(&$_params) 
    {
    
        global $gManagerFactory;

        $entityMgr = $gManagerFactory->getManager($_params['entity']);
        parent::Editor_Instantiate($_params);

        $this->state  = Request::$r->_state;

        //if there is an error, save extra processing.
        if ($this->state == $this->kErrorState) {
            return ;
         }

        $mod      = Request::$r->_mod;
        $dt       = Request::$r->_dt;
        $cat      = Request::$r->_cat;
        $ent      = Request::$r->_ent;
        $srcdoc   = Request::$r->_srcdoc;
        $copymode = Request::$r->_copymode;
        $derive   = Request::$r->_derive;

        import($mod.'documentmanager');
        if ($mod) { 
            $this->MatchTemplates($_params, array('path' => 'DOC.WHENCREATED'), $whencreated);
            if ($whencreated) {
                foreach ( $whencreated as $k => $field) { 
                    $whencreated[$k]['value'] = GetCurrentDate();
                }
            }

            $this->MatchTemplates($_params, array('path' => 'DOC.DOCPARID'), $fields);
            if ($fields) {
                $docs = GetDocumentMenuList($mod, $cat); //GetDocumentParams($mod); 
                foreach ($docs as $doc) {
                    $ddlist[] = $doc['DOCID'];
                }
                foreach ( $fields as $k => $field) { 
                    if ($dt) {
                        $fields[$k]['value'] = $dt;
                        $fields[$k]['readonly'] = true;
                        $fields[$k]['type']['entity'] = $mod.'documentparams';
                    }
                    else {
                        $fields[$k]['required'] = 'true';
                        /** @noinspection PhpUndefinedVariableInspection */
                        $fields[$k]['type']['validvalues'] = $ddlist;
                        $fields[$k]['type']['ptype'] = 'enum';
                        $fields[$k]['type']['type'] = 'enum';
                    }
                }
            }

            $entityMgr->SetHomeModule($mod);

            $this->MatchTemplates($_params, array('path' => 'DOC.CUSTVENDID'), $fields2);
            foreach ( $fields2 as $k => $field) { 
                if ($mod == 'inv') {
                    $fields2[$k]['hidden'] = true;
                }
                else {
                    $fields2[$k]['value']    = $ent;
                    $fields2[$k]['fullname']    = ($mod == 'so') ? 'Customer' : _('Vendor');
                    $fields2[$k]['desc']        = ($mod == 'so') ? 'Customer' : 'Vendor';
                    $fields2[$k]['type']['entity'] = ($mod == 'so') ? 'customer' : 'vendor';
                    $fields2[$k]['type']['pickentity'] = ($mod == 'so') ? 'customerpick' : 'vendorpick';
                    $fields2[$k]['type']['ptype'] = 'ptr';
                    $fields2[$k]['type']['type'] = 'ptr';
                    if ($derive) {
                        $fields2[$k]['readonly'] = true;
                    }

                }
                $fields2[$k]['required'] = false;
            }
            $this->MatchTemplates($_params, array('path' => 'DOC.CREATEDFROM'), $fields3);

            foreach ( $fields3 as $k => $field) { 
                if ($derive) {
                    $fields3[$k]['readonly'] = true;
                } else {
                    $fields3[$k]['readonly'] = false;
                }
                $fields3[$k]['type']['entity'] = $mod.'document';
                $fields3[$k]['value'] = $srcdoc;
            }
            $this->MatchTemplates($_params, array('path' => 'COPYMODE'), $fields4);
            foreach ( $fields4 as $k => $field) { 

                if ($derive) {
                    $fields4[$k]['readonly'] = true;
                } else {
                    $fields4[$k]['readonly'] = false;
                }
                $fields4[$k]['value'] = $copymode;
            }

        }
    }

    /**
     * ShowPreListerEditorInfo
     */
    function ShowPreListerEditorInfo()
    {
        // Does nothing allow to override
        $msg = $this->GetMessage();
        if (!$msg) {
            $msg = Request::$r->_msg;
        }
        if ($msg) {
        ?>
         <center>
         <table border="0" cellpadding="1" cellspacing="0" width="70%" bgcolor="#999966">
          <tr>
        <td valign="top">

        <table border="0" cellpadding="4" cellspacing="0" width="100%" bgcolor="#FFFFCC">
         <tr>
          <td valign="middle" align="center">
          <font face="Verdana, Arial, Helvetica" size="2"><b><? echo $msg; ?></b></font>
          </td>
         </tr>
        </table>

        </td>
       </tr>
         </table>
         </center>
        <?
        $this->message='';
        }
    }


    /**
     * Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     * 
     * @param bool $addYuiCss include the YUI css files
     */
    function showScripts($addYuiCss = true)
    {
        parent::showScripts($addYuiCss);
        $mod = Request::$r->_mod;
    ?>
     <script language=javascript>
     function CustomizeURL() {
      if (arguments.length == 1) {
				alert('CustomizeURL needs at least one argument.  USAGE: CustomizeURL(script,args...)');
      }
      var layer = document.forms[0]._currentlayer.value;

      var base = arguments[0];
      var url = '';
      for(var i = 1; i < arguments.length; i++) {
				url += ((i == 1) ? '' : '&') + arguments[i];
      }

      mod = '<?= $mod ?>' ;

      if (is.nav) {
				dt		=	document.layers[layer].ownerDocument.forms[0].elements['_obj__DOC__DOCPARID'].value;
				ID 		=	(mod != 'inv') ? document.layers[layer].ownerDocument.forms[0].elements['_obj__DOC__CUSTVENDID'].value : '' ;
				t_arr = ID.split("--");
				ID = t_arr[0];

				mode 	=	document.layers[layer].ownerDocument.forms[0].elements['_obj__COPYMODE'].value;
      }
      else {
				dt 		= document.all[layer].ownerDocument.forms[1].elements['_obj__DOC__DOCPARID'].value;
				ID 		= (mod != 'inv') ? document.all[layer].ownerDocument.forms[1].elements['_obj__DOC__CUSTVENDID'].value : '' ;
				t_arr = ID.split("--");
				ID = t_arr[0];

				mode	= document.all[layer].ownerDocument.forms[1].elements['_obj__COPYMODE'].value;
      }
			
      url = base + '?' + url + '&.dt=' + dt + '&.id=' + ID + '&.cmod=' + '<?= $mod ?>' + '&.mode=' + mode;
      return url;
     }

    function SubmitContinue() {
	   with (document.forms[0]) {
      elements['<? echo $this->kAction; ?>'].value='<? echo $this->kCreateAction ; ?>';
      if(BeforeSubmit()){
				submit();
      }
      return false;
	   }
    }


    function ToggleLayer(selection) {
     return SubmitContinue();
    }


     </script>

    <?
    }


}
