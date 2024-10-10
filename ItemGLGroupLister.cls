<?
import('ItemGLGroupLister');

/**
 * Class ItemGLGroupLister
 */
class ItemGLGroupLister extends NLister
{

    function __construct()
    {
        $helpIDs = array (
        'inv' => 'Viewing_and_Managing_the_Item_GL_Groups_List',              
        'po' => 'Viewing_and_Managing_the_Item_GL_Groups_List',                           
        'so' => 'Viewing_and_Managing_the_Item_GL_Groups_List',                                   
        );
        $helpfile = $helpIDs[Request::$r->_mod];


        parent::__construct(
            array(
            'entity'        =>  'itemglgroup',
            'fields'        =>  array('NAME'),
            'helpfile'        => $helpfile,
            'enablemultidelete' => true
            )
        );
    }
}

