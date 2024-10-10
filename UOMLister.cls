<?

class UOMLister extends NLister
{

    public function __construct()
    {
        $helpIDs = array (
        'inv' => 'Viewing_and_Managing_the_Units_of_Measure_List',
        'po' => 'Viewing_and_Managing_the_Units_of_Measure_List',
        'so' => 'Viewing_and_Managing_the_Units_of_Measure_List',
        );
        $helpfile = $helpIDs[Request::$r->_mod];

        parent::__construct(
            array (
            'entity'        =>  'uom',
            'fields'        =>  array('NAME','ISSYSTEM','RECORDNO'),
            'helpfile'        => $helpfile,
            'title'            => 'IA.UNIT_OF_MEASURE_LISTER',
            'sortcolumn'    => 'NAME',
            'entitynostatus' => 1,
            'importtype'    => 'uom',
            )
        );
    }

    /**
     *
     */
    public function BuildTable()
    {
        parent::BuildTable();

        $fieldlabels    = array('IA.UNIT_GROUP');
        $fields        = array('NAME');

        $this->SetOutputFields($fields, $fieldlabels);
    }

    /**
     * @param int $i
     * @param array $vals
     *
     * @return array
     */
    public function calcEditUrlParms($i, $vals)
    {        
        //if ($this->table[$i]['ISSYSTEM'] == 'true') {
        //	return array();
        //}
        $vals['urlargs']['.grpkey'] = $this->table[$i]['RECORDNO'];

        return parent::calcEditUrlParms($i, $vals);
    }

    /**
     * @param int $i
     * @param array $vals
     *
     * @return array
     */
    public function calcViewUrlParms($i, $vals)
    {        
        //if ($this->table[$i]['ISSYSTEM'] == 'true') {
        //	return array();
        //}
        $vals['urlargs']['.grpkey'] = $this->table[$i]['RECORDNO'];

        return parent::calcViewUrlParms($i, $vals);
    }

    /**
     * @param int $i
     * @param array $vals
     *
     * @return array
     */
    public function calcDeleteUrlParms($i, $vals)
    {
        if ($this->table[$i]['ISSYSTEM'] == 'true')
        {
            return array();
        }

        return parent::calcDeleteUrlParms($i, $vals);
    }
}


