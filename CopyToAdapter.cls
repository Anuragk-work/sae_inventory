<?php
/**
 * Adapter class for changing the source object of a "Copy to" action.
 *         override this class to provide specific behavior when copying from an object that is not a Document.
 *         At the time of creation of this class, the only override is to provide code
 *         to copy from a Project Change Order to a Sales Order.
 *
 * @author    Garry Jost <garry.jost@sage.com>
 * @copyright 2021 Intacct Corporation All Rights Reserved
 */
class CopyToAdapter
{
    /**
     * @param array &$params object parameters
     */
    public function changeEntity(&$params)
    {
        // for base class, don't do anything (leave entity as is)
    }

    /**
     * @param string $recalledID the ID of source object
     *
     * @return string doc type
     */
    public function getThisDocType($recalledID)
    {
        return ($recalledID == '') ? null : GetDocumentType($recalledID); // default behavior
    }

    /**
     * @param string $mod the module 'so' or 'po'
     * @param string $srcdoctype the source doc type
     *
     * @return object source manager
     */
    public function createSourceManager($mod, $srcdoctype)
    {
        global $gManagerFactory;

        // this is default behavior
        return $gManagerFactory->getManager($mod . "document", true, array('DOCTYPE' => $srcdoctype));  // default behavior
    }

    /**
     * @param array $old the pco object be transformed
     * @param bool  $isRetainageEnabled true if retainage enabled in AP or AR and on TD
     *
     * @return array the pco object transformed to look like a Sales Order object
     *
     */
    public function transformToDocFormat($old, /** @noinspection PhpUnusedParameterInspection */ $isRetainageEnabled) : array
    {
        // $isRetainageEnabled not used in base class

        // default behavior is just leave it as is, because it is already in doc format
        return $old;
    }

    /**
     * @param object $sourceObject the source object
     *
     * @return object source manager
     */
    public function getSourceManager($sourceObject)
    {
        // this is default behavior
        return $sourceObject->GetManager($sourceObject->getEntity());  // default behavior
    }

    /**
     * @param array &$vars the editor globals
     */
    public function getEditorGlobals(&$vars)
    {
        // default behavior: do not add any global variables
    }
}