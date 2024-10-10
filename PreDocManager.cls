<?
import('entitymanager');

/**
 * Class PreDocManager
 */
class PreDocManager extends EntityManager
{
    /**
     * Get a single record
     *
     * @param string        $ID
     * @param string[]|null $fields
     *
     * @return array|false
     */

    function get($ID, $fields = null) {
        return true; 
    }

    /**
     *  Wrapper for php5.4 conversion.  Provides by-value wrapper for Add.  Can be removed, and AddByRef renamed to Add,
     * when it's verified that it's safe to call this class' Add by-reference.
     *
     * @param array $values
     *
     * @return bool
     */


    protected function regularAdd(&$values)
    {
        return $this->AddByRef($values);
    }

    /**
     * @param array $values
     *
     * @return bool
     */
    function AddByRef(&$values) 
    {
        global $gManagerFactory;

        $mod    = Request::$r->_mod;
        $done    = Request::$r->_done;
        $opid    = GetOperationId($mod . '/lists/' . $mod . 'document/create');

        $dockey = $values['DOC']['CREATEDFROM'];
        list($ID)    = explode('--', $values['DOC']['CUSTVENDID']);
        $date    = $values['DOC']['WHENCREATED'];

        global $gErr;
        if ($dockey) {
            $copymode = $values['COPYMODE'] ;
            // Get the recalled doctype
            $dmgr = $gManagerFactory->getManager('document');
            $raw = $dmgr->GetRaw($dockey);
            $ok = isset($raw[0]);

            if ($ok) {
                if ($raw[0]['STATE'] == 'D' && $copymode != 'Copy Only') {

                    $msg = 'Document '.$dockey.' is closed. Unable to recall';
                    $gErr->addIAError('INV-0763', __FILE__ . ':' . __LINE__, $msg, ['DOCKEY' => $dockey]);
                    $ok = false;
                }

                if (($raw[0]['STATE'] == 'C' || $raw[0]['STATE'] == 'L' ) && $copymode != 'Copy Only') {

                    $msg = 'Document '.$dockey.' is converted. Unable to recall';
                    $gErr->addIAError('INV-0764', __FILE__ . ':' . __LINE__, $msg, ['DOCKEY' => $dockey]);
                    $ok = false;
                }
            }

            if ($ok) {

                //Get the ID
                $docparmgr = $gManagerFactory->getManager('documentparams');
                $res = $docparmgr->DoQuery('QRY_DOCUMENTPARAMS_GET_DOCID_FROM_RECORDNO', $raw[0]['DOCPARKEY']);
                $recalledFrom = $res[0]['DOCID'];

                $mgr = $gManagerFactory->getManager('docrecalls');
                $qry = 'QRY_DOCRECALLS_GETALLOWED_VID';
                $args = array ($values['DOC']['DOCPARID']);
                $result = $mgr->DoQuery($qry, $args);
                $flag = false;

                foreach ( $result as $row) {
                    if ($row['DOCID'] == $recalledFrom) {
                        $flag = true;
                        break;
                    }
                }
            }
            else {
                // ADD ERROR HERE
                $msg = 'Error fetching recalled document during validation.';
                $gErr->addIAError('INV-0765', __FILE__ . ':' . __LINE__, $msg, []);
                return false;
            }
            if (!$flag) {
                // ADD ERROR HERE
                $msg = "$dockey is not an allowed document for recall.";
                $gErr->addIAError('INV-0766', __FILE__ . ':' . __LINE__, $msg, ['DOCKEY' => $dockey]);
                return false;
            }
        }
        elseif ($mod != 'inv') {
            $IDtype = ($mod == 'po' ) ? _('Vendor') : 'Customer';
            if (!$ID) {
                $msg = sprintf("Either a %s or an existing transaction is required.", $IDtype);
                $gErr->addIAError('INV-0767', __FILE__ . ':' . __LINE__, $msg, ['IDTYPE' => $IDtype]);
                return false;
            } else {
                $custvendMgr = $gManagerFactory->getManager(isl_strtolower($IDtype));
                $custvendObj = $custvendMgr->GetRaw($ID); 
                
                $msg = sprintf('%1$s ID \'%2$s\' is not valid.', $IDtype, $ID);
                if (!isset($custvendObj) || !$custvendObj) {
                    $gErr->addIAError('INV-0768', __FILE__ . ':' . __LINE__, $msg, ['IDTYPE' => $IDtype, 'ID' => $ID]);
                    return false;
                }
            }
        }

        $_sess = Session::getKey();
        $url = 'editor.phtml?.sess='.$_sess.'&.frompre=1&.op='.$opid.'&.date='.urlencode($date).'&.dt='.urlencode($values['DOC']['DOCPARID']);
        /** @noinspection PhpUndefinedVariableInspection */
        if ( $dockey && $copymode == 'Copy Only') {
            $url .= '&.entid='.urlencode($ID).'&.r='.urlencode($dockey).'&.copymode='.$copymode;
        } /** @noinspection PhpUndefinedVariableInspection */ elseif ( $dockey && $copymode != 'Copy Only') {
            $url .= '&.r='.urlencode($dockey).'&.copymode='.$copymode;
        } else {
            $url .= '&.entid='.urlencode($ID); 
        }

        Fwd($url, $done);
        return true;
    }


}
