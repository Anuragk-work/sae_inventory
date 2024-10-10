<?php
/**
 * class COGSClosedJeLister extends NLister
 */

/**
 * Class DocumentLister
 */
class COGSClosedJeLister extends NLister
{
    /**
     * @var array  $oldparams
     */
    private $oldparams;

    /**
     * @param array $_params Initial params
     */
    public function __construct($_params = array())
    {


        $myparams = array(
            'entity' => 'COGSClosedJe',
            'title' => 'IA.COGSCLOSEDJE_LISTER',
            'fields' => array(
                'RECORDNO',

                // these are filter/command parameters:
                'ASOFDATE',

                // filter parameters that are also returned in the rows:
                'ITEMID',
                'WAREHOUSEID',
                'LOCATIONID',

                // returned stuff for 'things needing posting':
                'DOCUMENTNAME',
                'CUSTOMERID',

                // and additional fields for 'posts to be removed':
                'NEEDSADJUSTMENT',
            ),
            'sortcolumn'    => 'RECORDNO:d, ASOFDATE:d',
            'helpfile' => '',

        );

        $_params = array_merge($_params, $myparams);
        parent::__construct($_params); 
    }


    /**
     * @return array
     */
    function BuildQuerySpec()
    {

        $initial = parent::BuildQuerySpec();
        $querySpec['selects'][] = "NEEDSADJUSTMENT";

        return $initial;
    }

    function BuildTable()
    {
        parent::BuildTable();

    }



    /**
     * calcParams
     *
     * @param array $_params initial parameter list
     *
     * @return array updated parameter list
     */
    function calcParams($_params)
    {
        $this->oldparams = $_params;
        $_params['OLDPARAMS'] = $_params;
        $_params =  parent::CalcParams($_params);

        return $_params;
    }



}
