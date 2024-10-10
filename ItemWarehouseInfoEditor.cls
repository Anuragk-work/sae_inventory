<?
import('editor');

/**
 * Class ItemWarehouseInfoEditor
 */
class ItemWarehouseInfoEditor extends Editor
{
    /**
     * @param array $_params
     */
    function Editor_Instantiate(&$_params)
    {
        global $kINVid;
        parent::Editor_Instantiate($_params);
        
        //check whether enable bin is set to true in inventory setup screen. 
        GetModulePreferences($kINVid, $prefs); 
        $hiddenFields = array();

        //Show serial option only if enable serialization is set to true in inventory setup screen.
        if($prefs['ENABLESERIAL']!='T') {
            $hiddenFields[]='ENABLE_SERIALNO';
            $hiddenFields[]='SERIAL_MASKKEY';
        }

        //Show lot category option only if enable lots is set to true in inventory setup screen.
        if($prefs['ENABLELOT']!='T') {
            $hiddenFields[]='ENABLE_LOT_CATEGORY';
            $hiddenFields[]='LOT_CATEGORYKEY';
        }

        //Show bins option only if enable bin is set to true in inventory setup screen.
        if($prefs['ENABLEBIN']!='T') {
            $hiddenFields[]='ENABLE_BINS';
            $hiddenFields[]='DEFAULT_AISLE';
            $hiddenFields[]='DEFAULT_ROW';
            $hiddenFields[]='DEFAULT_BIN';
        } else if (BinManager::areAdvanedBinsOn()) {
            $hiddenFields[]='DEFAULT_AISLE';
            $hiddenFields[]='DEFAULT_ROW';
        }
        if (count($hiddenFields)) {
            $this->HideFieldsByPath($_params, $hiddenFields);    
        }
    }

}
