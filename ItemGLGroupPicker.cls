<?

/**
 * Class ItemGLGroupPicker
 */
class ItemGLGroupPicker extends NPicker
{

    function __construct()
    {
        parent::__construct(
            array (
            'entity'        =>  'ItemGLGroup',
            'fields'        =>  array('NAME'),
            'helpfile'        => 'Locations_Lister',
            'title'            => 'IA.ITEM_GL_GROUP',
            'entitynostatus' => 1
            )
        );
    }
}

