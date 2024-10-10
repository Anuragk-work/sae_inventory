<?php
//=============================================================================
//
//  FILE:        ItemDataObject.cls
//  AUTHOR:      Vishwajit Pantvaidya
//  DESCRIPTION: In memory object representation of an item
//
//  (C)2000,2009 Intacct Corporation, All Rights Reserved
//
//  Intacct Corporation Proprietary Information.
//  This document contains trade secret data that belongs to Intacct
//  corporation and is protected by the copyright laws. Information herein
//  may not be used, copied or disclosed in whole or part without prior
//  written consent from Intacct Corporation.
//
//=============================================================================

/**
 * Represents the base item
 * Can be created from an item array having element ITEMID containing item id 
 *  
 * @author vpantvaidya
 */

/**
 * Class ItemDataObject
 */
class ItemDataObject
{
    /** @var array $properties */
    private $properties = array();

    /** @var string|null $id */
    private $id = null;
    
    /**
     * @param array $properties     should have element ITEMID containing item id
     */
    public function __construct($properties) 
    {
        $this->id = $properties['ITEMID'];
        $this->properties = $properties;
    }
    
    
    /**
     * Retrieve the id of the item
     *
     * @return string|null
     */
    public function getId()
    {
        return $this->id;
    }
      
      
    /**
     * Retrieve all properties
     *
     * @return array    the properties array
     */
    public function getProperties()
    {
        return $this->properties;
    }
      
      
    /**
     * Set all properties
     *
     * @param array $properties
     *
     * @return bool
     */
    public function setProperties($properties) 
    {
        $this->properties=$properties;
        return true;
    }
      
      
    /**
     * Retrieve the specified item property
     *
     * @param string    $property
     *
     * @return mixed
     */
    public function getProperty($property) 
    {
        return $this->properties[$property];
    }
      
      
    /**
     * Set the specified property
     *
     * @param string    $property       the property name
     * @param mixed     $value          the property value
     * @param bool      $overwrite      should an existing property with same name be overwritten
     *
     * @return bool                     when overwrite=true, returns true
     *                                  when overwrite=false, returns false if property already exists
     */
    public function setProperty($property,$value,$overwrite=true) 
    {
        if ( $overwrite===true || ($overwrite===false && !isset($this->properties[$property])) ) {
            $this->properties[$property]=$value;
            return true;
        } else {
            return false;
        } 
    }
      
      
    /**
     * Check if the given property is set in the item.
     *
     * @param string    $property   the property name
     *
     * @return bool
     */
    public function hasProperty($property) 
    {
        return isset($this->properties[$property]);
    }
    
    
    /**
     * Check if the given item is a stockable kit
     *
     * @return bool
     */
    public function isStockableKit() 
    {
        return false;
    }

    /**
     * Noinspection neccessary due to child class overriding the method.
     * Cannot be an abstract class since ItemDataObject(this class) is intantiated elsewhere.
     *
     * @param array     $componentObj
     * @param int       $index
     * @param bool      $overwrite
     *
     * @return bool
     */
    public function setComponent(
        /** @noinspection PhpUnusedParameterInspection */ $componentObj,
        /** @noinspection PhpUnusedParameterInspection */ $index,
        /** @noinspection PhpUnusedParameterInspection */ $overwrite=true)
    {
        return true;
    }
    
    
}


