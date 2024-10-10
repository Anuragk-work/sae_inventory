<?php

/**
 * Manager class for warehouse transfer entry
 * 
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2000 Intacct Corporation All, Rights Reserved
 */

/**
 * Owned object class for warehouse transfer entry
 */
class ICTransferItemManager extends OwnedObjectManager
{

    /**
     * @param array $params Params array
     */
    public function __construct($params = array())
    {
        parent::__construct($params);
    }

    /**
     * @return bool
     */
    function MergeTableInfo()
    {
        return true;
    }

    /**
     * Dynamically populates the entity with the schema and object
     * information
     */
    function MergeObjectSchema()
    {
        parent::MergeObjectSchema();

        $schema = &$this->_schemas[$this->_entity]['schema'];
        $dimFields = $this->GetDimensionFields();
        if ($dimFields && count($dimFields) > 0) {
            foreach ($dimFields as $field) {
                $schema[strtoupper($field['dimfieldid'])] = 'docentry.' . $schema[strtoupper($field['dimfieldid'])];
            }
        }
    }

    /**
     *MergeSchemaChildren
     */
    function MergeSchemaChildren() 
    {
        $origChildren = $this->_schemas[$this->_entity]['children'];
        parent::MergeSchemaChildren();
        $children =& $this->_schemas[$this->_entity]['children'];
        
        $childrenDiff = array_diff_assoc($children, $origChildren);
        
        foreach ($childrenDiff as $key=> $child) {
            $origChildren['docentry']['children'][$key] = $child;    
        }

        $children = $origChildren;
    }

    /**
     * Override base function to handle task dimension dbfkid difference for docentry..
     *
     * @param array $dimInfo
     *
     */
    function SetDimensionFields(&$dimInfo)
    {
        // for docentry, task dimension has different dbfkid..
        if ( array_key_exists('task', $dimInfo)) {
            $dimInfo['task']['dimfieldid'] = 'taskkey';
            $dimInfo['task']['dimdbkey'] = 'TASKKEY';
            $dimInfo['task']['object_relation'] = array(
                'fkey' => 'taskkey', 'invfkey' => 'record#', 'table' => 'task', 'join' => 'outer'
            );
            $dimInfo['task']['referentialConstraints'] = array('project' => 'PROJECTDIMKEY');
        }

        parent::SetDimensionFields($dimInfo);
    }
}