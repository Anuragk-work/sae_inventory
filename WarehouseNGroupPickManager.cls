<?php

/**
 * Manager class for Warehouse and Group Picker
 * 
 * @author    Anish <anishk@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Class WarehouseNGroupPickManager
 */
class WarehouseNGroupPickManager extends WarehousePickManager
{

    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        parent::__construct($params);
    }

    /**
     * @param string $field
     *
     * @return array
     */
    function & GetFieldInfo($field)
    {
        $info = parent::GetFieldInfo($field);
        if ( $field == 'TYPE' ) {
            $dict = Dictionary::getInstance();

            $info['formula'] = array(
                'fields' => array('TYPEUI'),
                'function' => "case when \${1} = 'Warehouse' then '" . $dict->GetRenamedText('Warehouse') .
                "' else \${1} end ",
            );
        }

        return $info;
    }

    /**
     * Hack to show calculated field in the picker. 
     * It is different than Lister since it does not have alias like C0, C1
     * 
     * @param array       $processed
     * @param array|false $firstRow  First row returned by the query, not necessarily the first row returned from the function.
     *
     * @return array
     */
    public function runGetList($processed, &$firstRow = null)
    {
        foreach ( $processed['COLUMN_MAP'] as $key => $columnMap ) {
            foreach ( $columnMap as $ckey => $val ) {
                if ( $val == 'TYPEUI' ) {
                    $processed['COLUMN_MAP'][$key][$ckey] = 'TYPE';
                }
            }
        }

        return parent::runGetList($processed, $firstRow);
    }

}


