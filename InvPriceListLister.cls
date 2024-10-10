<?

/**
 *    FILE: InvPriceListLister.cls
 *    AUTHOR: John P. Campbell
 *    DESCRIPTION:
 *
 *    (C) 2000, Intacct Corporation, All Rights Reserved
 *
 *    This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 *    herein may not be used, copied or disclosed in whole or in part
 *    without prior written consent from Intacct Corporation.
 */


import('NLister');

/**
 * Class InvPriceListLister
 */
class InvPriceListLister extends NLister
{
    /**
     * @var string[]
     */
    protected $additionalTokens = [
        'IA.DETAILS',
    ];

    /** @var string $mod */
    var $mod='inv';

    function __construct()
    { 
        $entity = $this->mod.'pricelist';

        parent::__construct(
            array (
            'entity'        =>  $entity,
            'fields'        =>  array(
            'NAME',
            'SALEPURCHASE',
            'DATEFROM',
            'DATETO',
            "'URL'"
            ),
            'importtype'    => 'pricelist',
            'helpfile'      => 'Viewing_and_Managing_the_List_of_Price_Lists'
            )
        ); 
    }

    /**
     *
     */
    function BuildTable() 
    {
        parent::BuildTable();
        $mod = Request::$r->_mod;
        $opID = GetOperationId($mod . '/lists/' . $mod . 'pricelistentry');

        foreach($this->table as $key => $row) {
            $listID    = urlencode($row['NAME']);
            $d1        = urlencode($row['DATEFROM']);
            $d2        = urlencode($row['DATETO']);

            $owner = $this->GetObjectOwnership($key);
            $ownerloc = $this->GetObjectOwnerLocation($key);

            $url = 'lister.phtml?.op='.$opID.'&.plid='.$listID.'&.d1='.$d1.'&.d2='.$d2.'&'.OptDone(ScriptRequest());

            //If MEGA and object is owned below us, regenerate base url to be slide-in
            if($owner > 0 && $ownerloc) {
                $url = $this->_calcSlideUrl($url, $ownerloc);
            }

            $this->table[$key]["'URL'"] =     "<a tabIndex=\"-1\" href=\"" . $url ."\" ". ">" .GT($this->textMap, 'IA.DETAILS'). "</a>";

        }

    }

    /**
     * @param string $_pref
     *
     * @return string
     */
    function GetPreference($_pref) 
    {
        $mm = $this->getEntityMgr()->_MM;
        $val = $mm ? $mm->GetPreference($_pref) : null;

        if ($val && $_pref == 'INVPRICELIST.LISTERFIELDS') {
            $val .= ":'URL'";
        }

        return $val ?: $this->_params[$_pref];
    }

}
