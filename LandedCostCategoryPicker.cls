<?php

class LandedCostCategoryPicker extends NPicker {

    /**
     * LandedCostCategoryPicker constructor
     */
	public function __construct()
    {
		parent::__construct(
			array (
				'entity'    	=>  'landedcostcategory',
				'fields'		=>  array('LCCATID','LCCATNAME'),
				'helpfile'		=> 'Locations_Lister',
				'title'			=> 'IA.LANDED_COSTS_CATEGORY',
				'pickfield'		=> 'LCCATID',
                'addlPickFields'=> array('LCCATNAME'),
			)
		);
	}
}


