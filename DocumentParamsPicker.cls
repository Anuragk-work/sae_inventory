<?

/**
 * Class DocumentParamsPicker
 *
 * @author    intacct
 * @copyright 2000-2017 Intacct Corporation
 *
 * This document contains trade secret data that belongs to Intacct
 * Corporation and is protected by the copyright laws.  Information
 * herein may not be used, copied or disclosed in whole or in part
 * without prior written consent from Intacct Corporation.
 */
class DocumentParamsPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array(
                'entity'        => 'documentparams',
                'fields'        => array('DOCID'),
                'pickfield'     => 'DOCID',
                'helpfile'      => 'Locations_Lister',
            'title'            => 'Document Parameters'
            )
        );
    }

    /**
     * Overrides the method.
     *
     * @return array
     */
    function BuildQuerySpec() 
    {
        $querySpec = parent::BuildQuerySpec();

        $salecon = Request::$r->_salecon;
        $r = Request::$r->_r;

        if($salecon=='T') {
            $cny = GetMyCompany();

            $subquery = array("
				SELECT docpar.record#
				FROM 
					 docpar, docrecalls, docpar recdpr 
				WHERE 
					  docpar.latestversionkey is null 
					  and docpar.sale_pur_trans = 'S' 
					  and docpar.status = 'T' 
					  and docpar.RECORD# = docrecalls.DOCPARKEY (+) 
					  and docrecalls.RECDOCPARKEY = recdpr.record# 
					  and recdpr.docid = (select docpar.docid from docpar,dochdr
						  where 
								docpar.record# = dochdr.docparkey and
								docpar.cny# = $cny 
								and dochdr.cny# = $cny
								and dochdr.docid = '". $r ."'".")
					  and recdpr.record# = docrecalls.recdocparkey 
					  and recdpr.cny# (+) = $cny 
					  and docpar.cny# = $cny 
					  and docrecalls.CNY# (+) = $cny"
            );
            $querySpec['filters'][0][] = array('RECORDNO', 'INSUBQUERY', $subquery);
        }

        $this->AddFilters($querySpec);
        return $querySpec;
    }

    /**
     * Overrides the method.
     *
     * @return array
     */
    function BuildQuerySpecAll() 
    {
        $qspec = parent::BuildQuerySpecAll();

        $salecon = Request::$r->_salecon;
        $r = Request::$r->_r;

        if($salecon=='T') {
            $cny = GetMyCompany();

            $subquery = array("
				SELECT docpar.record#
				FROM 
					 docpar, docrecalls, docpar recdpr 
				WHERE 
					  docpar.latestversionkey is null 
					  and docpar.sale_pur_trans = 'S' 
					  and docpar.status = 'T' 
					  and docpar.RECORD# = docrecalls.DOCPARKEY (+) 
					  and docrecalls.RECDOCPARKEY = recdpr.record# 
					  and recdpr.docid = (select docpar.docid from docpar,dochdr
						  where 
								docpar.record# = dochdr.docparkey and
								docpar.cny# = $cny 
								and dochdr.cny# = $cny
								and dochdr.docid = '". $r ."'".")
					  and recdpr.record# = docrecalls.recdocparkey 
					  and recdpr.cny# (+) = $cny 
					  and docpar.cny# = $cny 
					  and docrecalls.CNY# (+) = $cny"
            );
            $qspec['filters'][0][] = array('RECORDNO', 'INSUBQUERY', $subquery);
        }

        $this->AddFilters($qspec);
        return $qspec;

    }

    /**
     * Adds the fileter to the query spec.
     *
     * @param array $qrySpec
     */
    function AddFilters(&$qrySpec) 
    {
        $mod = Request::$r->_mod;

        if($mod=='po') {
            $module = 'P';
        }else if($mod=='so') {
            $module = 'S';
        }else if($mod=='inv') {
            $module = 'I';
        }

        if (isset($module) && $module != '') {
            $qrySpec['filters'][0][] = array('documentparams.sale_pur_trans', "=", $module);
        }

    }

    /**
     * @return string
     */
    function genGlobs()    
    {
        $salecon = Request::$r->_salecon;
        $r = Request::$r->_r;
        $mod = Request::$r->_mod;

        $ret = parent::genGlobs();
        $ret .= "<g name='.salecon'>" . $salecon . "</g>";
        $ret .= "<g name='.r'>" . $r . "</g>";
        $ret .= "<g name='.mod'>" . $mod . "</g>";
        return $ret;
    }

}
