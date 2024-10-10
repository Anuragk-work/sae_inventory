<?php
import('DocumentPicker');

/**
 * Class InvDocumentPicker
 */
class InvDocumentPicker extends DocumentPicker
{

    function __construct()
    {
        // TODO: Why are we skipping constructors?
        NPicker::__construct(
            array(
            'entity'        => 'invdocument',
            'fields'        => array('DOCID', 'CREATEDFROM', 'WHENCREATED', 'STATE'),
            'pickfield'     => 'DOCID',
            'title'            => "IA.INVENTORY_CONTROL_TRANSACTION",
            'sortcolumn'    => 'WHENCREATED:d',
            )
        );
    }
}
