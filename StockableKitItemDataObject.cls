<?php
//=============================================================================
//
//  FILE:        StockableKitItemDataObject.cls
//  AUTHOR:      Vishwajit Pantvaidya
//  DESCRIPTION: In memory object representation of a stockable kit item
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
 * Represents the stockable kit item definition as a tree structure 
 * with each stockable kit node just maintaining its immediate children.
 *  
 * @author vpantvaidya
 */
define("STOCKABLE_KIT", 'Stockable Kit');
define("REGULAR_KIT", 'Kit');

/**
 * Class StockableKitItemDataObject
 */
class StockableKitItemDataObject extends ItemDataObject
{
    
    /** @var array $components */
    private $components = array();

    /** @var array $componentArrayIndexes */
    private $componentArrayIndexes = array();
    
    
    /**
     * @param array $properties
     */
    public function __construct($properties) 
    {
        
        unset($properties['COMPONENT']);
        parent::__construct($properties);
        
    }
    
    
    /**
     * Add items from the specified array as stkit components
     *
     * @param array $componentsArray      may be multilevel i.e. contain components for lowerlevel stkits also
     *
     * @return $this
     */
    public function addComponentsArray($componentsArray) 
    {
        
        $stkits=array();
        $currentStKit=$this;
        $prevItemObj=null;
        // Setting 
        $prevlevel=1;
        foreach($componentsArray as $k => $item) {
            
            $currlevel=$item['ITEMLEVEL'];
            
            // Remove any components if present
            unset($item['COMPONENT']);
            // Passed components array from kit analysis report has component_id not itemid
            $item['ITEMID']=$item['COMPONENT_ID'];
            unset($item['COMPONENT_ID']);
            
            // Process current item and create the appropriate object for it
            if ( ($item['ITEMTYPE']==STOCKABLE_KIT) || ($item['ITEMTYPE']==REGULAR_KIT) ) {
                // Even if item is an SK, construct it using only its own properties
                $currentItemObj=new StockableKitItemDataObject($item);
            } else {
                $currentItemObj=new ItemDataObject($item);
            }

            // Levels decide which stockable kit is the parent of the current item
            if ($currlevel > $prevlevel) {
                // prev item was a stkit, current item is a child of it   
                // put the current stkit on the stack and make the previous item as the current stkit
                array_push($stkits, $currentStKit);
                $currentStKit=$prevItemObj;
            } else if ($currlevel<$prevlevel) {
                // Stkit ended with the previous component iteration
                // Discard all stkits from the stack upto current level
                for ($i=$prevlevel;$i>$currlevel;$i--) {
                    $currentStKit=array_pop($stkits);
                }
            } else {
                //Same kit continues - continue adding components to it
            }
            if($currentStKit) {
                $currentStKit->setComponent($currentItemObj, $k, true);
            }

            
            //Prepare variables for processing next row
            $prevlevel=$currlevel;
            $prevItemObj=$currentItemObj;
        }
        return $this;
        
    }
    
    
    /**
     * * Retrieve the array index for the specified componentid
     *
     * @param string    $id
     *
     * @return int
     */
    public function getArrayIndex($id) 
    {
        return $this->componentArrayIndexes[$id];
    }
      
      
    /**
     * @param string $id
     *
     * @return StockableKitItemDataObject|ItemDataObject
     */
    public function getComponent($id) 
    {
        return $this->components[$id];
    }
      
      
    /**
     * Retrieve all stkit components
     *
     * @return array    components - array of component objects
     */
    public function getComponents()
    {
        return $this->components;
    }
      
      
    /**
     * @param StockableKitItemDataObject|ItemDataObject $componentObj
     * @param int                                       $index
     * @param bool                                      $overwrite
     *
     * @return bool
     */
    public function setComponent($componentObj,$index,$overwrite=true) 
    {
        $compId=$componentObj->getId();
        if ( $overwrite===true || ($overwrite===false && $this->getComponent($compId)===null) ) {
            $this->components[$compId]=$componentObj;
            $this->componentArrayIndexes[$compId]=$index;
            return true;
        } else {
            return false;
        } 
    }
      
      
    /**
     * Check if the stockable kit has an item with this id
     *
     * @param string    $id     id of the item id to be checked for existence
     *
     * @return bool
     */
    public function hasComponent($id) 
    {
        return isset($this->components[$id]);
    }
    
    
    /**
     * Check if the given item is a stockable kit
     *
     * @return bool
     */
    public function isStockableKit()
    {
        return true;
    }
    
    
    /**
     * Output the stockable kit components as a tree
     *
     * @param StockableKitItemDataObject    $stkitObj
     * @param string $tree
     *
     */
    public static function getComponentsTree($stkitObj, &$tree) 
    {
        $comps=$stkitObj->getComponents();
        $level=1;
        foreach ( $comps as $comp) {
            if ($comp->isStockableKit()) {
                $tree.= '\n, '.str_repeat('\t', $level).$comp->getId().': ';
                self::getComponentsTree($comp, $tree);
            } else {
                $tree.= $comp->getId().', ';
            }
        }
    }
    
    
}


