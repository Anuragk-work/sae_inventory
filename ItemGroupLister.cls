<?php
/**
 * Lister class for Item Group
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Lister class for Item Group
 */

/**
 * Class ItemGroupLister
 */
class ItemGroupLister extends DimensionGroupLister
{

    public function __construct()
    {

        $params = array(
            'entity' => 'itemgroup',            
            'fields' => array('ID', 'NAME', 'GROUPTYPE', 'DIMGRPCOMP', 'DESCRIPTION'),
            'nonencodedfields' => array('RECORD_URL', 'MEMBERS'),
            'helpfile' => 'Viewing_and_Managing_Item_Groups',
            'enablemultidelete' => true
        );
        
        parent::__construct($params);
        $this->addLabelMapping('MEMBERS', 'IA.MEMBERS', true);
    }
}

