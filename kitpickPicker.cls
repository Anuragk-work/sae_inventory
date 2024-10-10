<?
class KitPickPicker extends NPicker
{

    public function __construct()
    {
        parent::__construct(
            array(
            'entity'        =>  'kitpick',
            'pickfield'        =>  'PICKID',
            'fields'        =>  array('PICKID', 'PRODUCTLINEID', 'STATUS'),
            'sortcolumn'    => 'ITEMID',
            )
        );
    }

    /**
     * @return array
     */
    public function BuildQuerySpecAll()
    {
        $qspec = parent::BuildQuerySpecAll();

        $this->AddFilters($qspec);

        return $qspec;
    }

    /**
     * @return array
     */
    public function BuildQuerySpec()
    {
        $ret = parent::BuildQuerySpec();
        
        $this->AddFilters($ret);

        return $ret;
    }

    /**
     * @param array $qrySpec
     */
    public function AddFilters(&$qrySpec)
    {
        global $kINVid;
        GetModulePreferences($kINVid, $prefs);
        //$itemMgr = $gManagerFactory->GetManager('item');
        //$allowLightAssembly = $itemMgr->EnableLightAssembly();

        // if kit is not enabled
        if ($prefs['LIGHTASSEMBLY']!='T') {
            $qrySpec['filters'][0][] = array('kitpick.itemtype', '<>', 'SK' );
        }
    }
}

