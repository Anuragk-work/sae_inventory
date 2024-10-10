<?php
/**
 * Trait for all customized error messages for scm macro
 *
 * @author    Senthil <skumar@intacct.com>
 * @copyright 2015 Intacct Corporation All, Rights Reserved
 */

/**
 * Trait for all customized error messages for scm macro
 */
trait SCMMacroErrorTrait
{
    /**
     * @param  string        $macroName
     * @param  string|int    $errNo
     * @param  string        $message
     * @param  string        $correction
     * @param  array         $params
     * @param  string        $errorCode
     * @param  array         $placeholder
     */
    public static function getMacroErrorMessage($macroName, $errNo, &$message, &$correction, $params=array(), &$errorCode = '', &$placeholder = array())
    {
        $message = '';
        $correction = '';
        $placeholder = [
            'desc1' => [],
            'desc2' => [],
            'corr' => [],
        ];
        switch ($errNo) {
            case 'MACRO001':
                self::messageForInactiveMacro($macroName, $message, $correction, $params, $errorCode, $placeholder);
                break;
            case 'MACRO002':
                self::messageForDeletingSource($macroName, $message, $correction, $params, $errorCode, $placeholder);
                break;
            case 'MACRO003':
                self::messageForDeletingSetup($macroName, $message, $correction, $params, $errorCode, $placeholder);
                break;
            case 'MACRO004':
                self::messageForDeletingSourceLine($macroName, $message, $correction, $params, $errorCode, $placeholder);
                break;
            case 'MACRO005':
                self::messageForModifyingSourceLine($macroName, $message, $correction, $params, $errorCode, $placeholder);
                break;
            case 'MACRO006':
                self::messageForRemovingLinkAtLine($macroName, $message, $correction, $params, $errorCode, $placeholder);
                break;                        
            case 'MACRO007':
                self::messageForRemovingLinkAtDoc($macroName, $message, $correction, $params, $errorCode, $placeholder);
                break;             
        }
    }

    /**
     * @param string $macroName
     * @param string $message
     * @param string $correction
     * @param array  $params
     */
    private static function messageForInactiveMacro($macroName, &$message, &$correction, $params, &$errorCode, &$placeholder)
    {
        switch ($macroName) {
            case self::DROPSHIP:
                $message = "Drop ship is inactive for transaction '" . $params['SOURCE'] . "'. Go to the Configure" .
                    " Order Entry screen and, for the sales transaction definition mapping for '" .
                    $params['SOURCE'] . "', select the Active checkbox. Then try again.";
                $correction = '';
                $errorCode = 'INV-1402';
                $placeholder['desc1'] = ['PARAMS_SOURCE' => $params['SOURCE']];
                break;
            case self::BTO:
                $message = "Buy to order is inactive for transaction '" . $params['SOURCE'] . "'. Go to the Configure" .
                    " Order Entry screen and, for the sales transaction definition mapping for '" .
                    $params['SOURCE'] . "', select the Active checkbox. Then try again.";
                $correction = '';
                $errorCode = 'INV-1403';
                $placeholder['desc1'] = ['PARAMS_SOURCE' => $params['SOURCE']];
                break;                
            default:
                $message = $macroName . " is inactive ";
                $correction = "Change your set up to make " . $macroName . " active ";
                $errorCode = 'INV-1404';
                $placeholder['desc1'] = ['MACRO_NAME' => $macroName];
                $placeholder['corr'] = ['MACRO_NAME' => $macroName];
        }

    }

    /**
     * @param string $macroName
     * @param string $message
     * @param string $correction
     * @param array  $params
     */
    private static function messageForDeletingSource($macroName, &$message, &$correction,
        /** @noinspection PhpUnusedParameterInspection */ $params, &$errorCode, &$placeholder)
    {
        switch ($macroName) {
            case self::DROPSHIP:
                $message = "The sales transaction includes drop-ship items and has associated purchase " .
                    "transactions that need to be deleted first. Go to the History tab on the sales transaction " .
                    "to find the associated drop-ship purchase transactions. Delete those purchase transactions, " .
                    "and then delete the sales transaction.";
                $correction = '';
                $errorCode = 'INV-1418';
                break;
            case self::BTO:
                $message = "The sales transaction includes buy-to-order items and has associated purchase " .
                    "transactions that need to be deleted first. Go to the History tab on the sales transaction " .
                    "to find the associated buy-to-order purchase transactions. Delete those purchase transactions, " .
                    "and then delete the sales transaction.";
                $correction = '';
                $errorCode = 'INV-1419';
                break;
            default:
                $message = "Could not delete this document as it has '" . $macroName . "' records linked ";
                $correction = "Delete the documents created thru $macroName first and try again";
                $errorCode = 'INV-1420';
                $placeholder['desc1'] = ['MACRO_NAME' => $macroName];
                $placeholder['corr'] = ['MACRO_NAME' => $macroName];
        }

    }

    /**
     * @param string $macroName
     * @param string $message
     * @param string $correction
     * @param array $params
     */
    private static function messageForDeletingSourceLine($macroName, &$message, &$correction,
        /** @noinspection PhpUnusedParameterInspection */ $params, &$errorCode, &$placeholder)
    {
        switch ($macroName) {
            case self::DROPSHIP:
                $message = "The entry includes drop-ship items and has associated purchase " .
                    "transactions that need to be deleted first. Go to the History tab on the sales transaction " .
                    "to find the associated drop-ship purchase transactions. Delete those purchase transactions, " .
                    "and then delete the entry.";
                $correction = '';
                $errorCode = 'INV-1415';
                break;
            case self::BTO:
                $message = "The entry includes buy-to-order items and has associated purchase " .
                    "transactions that need to be deleted first. Go to the History tab on the sales transaction " .
                    "to find the associated buy-to-order purchase transactions. Delete those purchase transactions, " .
                    "and then delete the entry.";
                $correction = '';
                $errorCode = 'INV-1416';
                break;
            default:
                $message = "Could not delete the entry as it has '" . $macroName . "' records linked ";
                $correction = "Delete the documents created thru $macroName first and try again";
                $errorCode = 'INV-1417';
                $placeholder['desc2'] = ['MACRO_NAME' => $macroName];
                $placeholder['corr'] = ['MACRO_NAME' => $macroName];
        }

    }

    /**
     * @param string $macroName
     * @param string $message
     * @param string $correction
     * @param array  $params
     */
    private static function messageForDeletingSetup($macroName, &$message, &$correction, $params, &$errorCode, &$placeholder)
    {
        switch ($macroName) {
            case self::DROPSHIP:
                $message = "Before you delete the mapping between a sales and purchase transaction definition," .
                    " you need to delete any associated drop-ship transactions. Consider creating a " .
                    "custom report to identify the drop-ship transactions for '" . $params['SOURCE'] .
                    "'. As an alternative, deselect the Active checkbox to make the definition " .
                    "mapping inactive. ";
                $correction = '';
                $errorCode = 'INV-1405';
                $placeholder['desc1'] = ['PARAMS_SOURCE' => $params['SOURCE']];
                break;
            case self::BTO:
                $message = "To delete the mapping between a sales and purchase transaction definition ".
                    "(or to disable buy to order), delete the associated buy-to-order transactions first.";
                $correction = "Consider creating a custom report to identify the buy-to-order transactions for ".
                    "'Sales Order'. As an alternative, deselect the Active checkbox to make the definition ".
                    "mapping inactive. ";
                $errorCode = 'INV-1406';
                break;
            default:
                $message = "Could not delete this document as it has '" . $macroName . "' records linked ";
                $correction = "Delete the documents created thru $macroName first and try again";
                $errorCode = 'INV-1407';
                $placeholder['desc1'] = ['MACRO_NAME' => $macroName];
                $placeholder['corr'] = ['MACRO_NAME' => $macroName];
        }

    }

    /**
     * @param string $macroName
     * @param string $message
     * @param string $correction
     * @param array  $params
     */
    private static function messageForModifyingSourceLine($macroName, &$message, &$correction,
        /** @noinspection PhpUnusedParameterInspection */ $params, &$errorCode, &$placeholder)
    {
        switch ($macroName) {
            case self::DROPSHIP:
                $message = "Sales transaction includes a drop shipped item. ". 
                    "Drop shipped line item(s) cannot be edited.";
                $correction = '';
                $errorCode = 'INV-1412';
                break;
            case self::BTO:
                $message = "Sales transaction includes a buy-to-order item. ". 
                    "buy-to-order line item(s) cannot be edited.";
                $correction = '';
                $errorCode = 'INV-1413';
                break;
            default:
                $message = "Cannot modify line that has macro linked";
                $correction = "Delete the documents created thru $macroName first and try again";
                $errorCode = 'INV-1430';
                $placeholder['corr'] = ['MACRO_NAME' => $macroName];
        }

    }

    /**
     * @param string $macroName
     * @param string $message
     * @param string $correction
     * @param array  $params
     */
    private static function messageForRemovingLinkAtLine($macroName, &$message, &$correction,
        /** @noinspection PhpUnusedParameterInspection */ $params, &$errorCode, &$placeholder)
    {
        switch ($macroName) {
            case self::DROPSHIP:
                $message = "Sales transaction includes a drop shipped item. ". 
                    "Drop shipped line items cannot be turned off.  Delete all the purchase ".
                    "transactions that are linked to the dropped ship line items, and then try again. ";
                $correction = '';
                $errorCode = 'INV-1409';
                break;
            case self::BTO:
                $message = "Sales transaction includes a buy-to-order item. ". 
                    "buy-to-order line items cannot be turned off.  Delete all the purchase ".
                    "transactions that are linked to the buy-to-order line items, and then try again. ";
                $correction = '';
                $errorCode = 'INV-1410';
                break;
            default:
                $message = "You cannot uncheck $macroName ";
                $correction = "Don't modify the line which has macro linked. ";
                $errorCode = 'INV-1411';
                $placeholder['desc1'] = ['MACRO_NAME' => $macroName];
        }

    }

    /**
     * @param string $macroName
     * @param string $message
     * @param string $correction
     * @param array  $params
     */
    private static function messageForRemovingLinkAtDoc($macroName, &$message, &$correction,
        /** @noinspection PhpUnusedParameterInspection */ $params, &$errorCode, &$placeholder)
    {
        switch ($macroName) {
            default:
                $message = "There is a child document created thru $macroName";
                $correction = "You cannot modify the document which has a child document linked.";
                $errorCode = 'INV-1408';
                $placeholder['desc1'] = ['MACRO_NAME' => $params['SOURCE']];
        }

    }    
}