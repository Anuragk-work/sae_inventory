<?php

/**
 *    This is the handler to print OE documents
 *
 *    @author    Valer Crisan <vcrisan@intacct.com>
 *    @copyright 2011 Intacct Corporation, All Rights Reserved
 */


/**
 * Print Handler for OE documents
 *
 * @author vcrisan
 */

/**
 * Class OEPrintHandler
 */
class OEPrintHandler extends EmailPrintHandler
{
    /**
     * @param array $params
     */
    public function __construct($params)
    {
        parent::__construct($params);
        $this->setMenuName($params['mod'] == 'so' ? I18N::getSingleToken('IA.ORDER_ENTRY') : I18N::getSingleToken('IA.PURCHASE_ORDERS'));
        $this->setJSFunctionName("documentLaunch");
    }


    /**
     * @param int $key the record key
     *
     * @return array|string
     */
    protected function getDocumentType($key)
    {
        return $this->custentityCache[$key];
    }

    /**
     * Return the XSL template for this record and document type
     *
     * @param int     $key        the record key
     * @param string  $docType    the document type
     * @param string  $xslformat  xsl format override
     *
     * @return string   the xsl document template
     *
     * @see EmailPrintHandler::getXSLTemplate()
     */
    protected function getXSLTemplate($key, $docType, $xslformat)
    {
        /** @var DocumentEditor|DocumentFormEditor $docEditor */
        $docEditor = $this->getEditor($docType);
        $xsl = $docEditor->GetXSLTemplate($key, $docType, $xslformat, []);
        return $xsl;
    }

    /**
     * Retrieve the xml representation of the record
     *
     * @param int $key the record key
     *
     * @return string
     *
     * @see EmailPrintHandler::getIndividualXML()
     */
    protected function getIndividualXML($key)
    {
        $docValues = $this->custentityCache[$key];
        $params = array(
            'ENTITYID'      => $docValues['ENTITYID'],
            'DOCCLASS'      => $docValues['DOCCLASS'],
            'DOCPARID'      => $docValues['DOCTYPE'],
            'DOCID'         => $key,
            'xsltemplateid' => $this->xslformat,
        );

        $editor = $this->getEditor($docValues['DOCTYPE']);
        if ( $editor instanceof FormEditor ) {
            // FormEditors that support xmldataraw
            assert($editor instanceof DocumentFormEditor || $editor instanceof SubLedgerTxnEditor);
            // Request::$r->_deliverymethod is set to xmldataraw above here to force DocumentFormEditor::Editor_Deliver
            // to return the xml
            assert(Request::$r->_deliverymethod == 'xmldataraw');

            /* @var FormEditor $editor */
            $editor->Editor_Deliver($params, false, $out);
        } else {
            // Editors that support xmldataraw
            assert($editor instanceof DocumentEditor || $editor instanceof InvoiceEditor);

            /* @var Editor $editor */
            $values['REC'] = $params;
            $editor->Editor_Deliver($params, $values, 'xmldataraw', false, $out);
        }

        return $out;
    }

    /**
     * Retrieve the FOP xml representation of the record
     *
     * @param string  $xml  the record in xml format
     * @param string  $xsl  the xsl template
     *
     * @return array  the FOP xml representation of the record
     *
     * @see EmailPrintHandler::getFO()
     */
    protected function getFO($xml, $xsl)
    {
        $arr = array();
        $xml = str_replace('<ROOT', '<OLDROOT', $xml);
        $xml = str_replace('</ROOT', '</OLDROOT', $xml);

        $arr['xml'] = $xml;
        $xml = '<ROOT>' . $xml . '</ROOT>';
        $ok = XSLTInProcess($xsl, $xml, $fo);

        if (!$ok) {
            global $gErr;
            $gErr->addIAError(
                'INV-0212',
                __FILE__ . ":" . __LINE__,
                "XSL Translation failed", []
            );
            include "../acct/popuperror.phtml";
            exit();
        }
        $arr['fo'] = $fo;
        return $arr;
    }

    /**
     * Retrieve the XML for pritning from the editor instance
     *
     * @param int $key          the key of the record to print
     * @param bool $isCustomDoc true if the request is for a custom doc
     *
     * @return string the xml
     */
    protected function getXMLForPrinting($key, $isCustomDoc)
    {
        return $this->getIndividualXML($key);
    }

    /**
     * Build the entity cache for the documents which need to be print/email 'ed.
     * The entity cache keeps the values so that they dont need to be refetched for
     * the same document if both print and email operations are selected.
     *
     * The format for custentityCache variable is:
     * array (
     *     "doc id" => array(
     *         "custentity" => "the entity id for the customer/vendor which the doc is related to",
     *         "documentdate" => "the date of creation for the document",
     *         "whendue" => "when the transaction due date",
     *         "custname" => "the name of the entity which the doc is related to"
     *     )
     * )
     */
    protected function preBuildDocuments()
    {
        //Get all Doc IDs selected
        $selectedDocID = INTACCTarray_merge(array_keys($this->printDocIds), array_keys($this->emailDocIds));
        $selectedDocID = array_unique($selectedDocID);

        // place ids in temp table so that clause can handle > 1000 invoices
        XACT_BEGIN("OEPrintHandler::preBuildDocuments");

        //$entitytype = 'docid';
        //DumpRecsToGlobalTempTable($selectedDocID, $tablename, $entitytype);
        //$selectedDocID = "(select ENTITYNO from $tablename where entitytype = '".$entitytype."')";

        $stmt = array('', GetMyCompany());

        if ($this->mod == 'po') {
            $stmt[0] = "select dp.docid doctype, dp.docclass, dh.docid, dh.state, dh.whencreated documentdate, dh.whendue, ".
                " v.entity custentity, v.vendorid entityid, v.name custname ".
                " from docparmst dp, dochdrmst dh, vendormst v ".
                " where dp.cny# = dh.cny# and dp.record# = dh.docparkey ".
                " and v.cny# = dh.cny# and v.entity = dh.vendentity and dh.cny# = :1 ";

            $stmt = PrepINClauseStmt($stmt, $selectedDocID, " and dh.docid ");
            $stmt[0] .= " order by dh.vendentity, dh.docid, dh.whencreated ";

            $this->rename = I18N::getSingleToken('IA.VENDOR');
        } else {
            $stmt[0] = "select dp.docid doctype, dp.docclass, dh.docid, dh.state, dh.whencreated documentdate, dh.whendue, ".
                " c.entity custentity, c.customerid entityid, c.name custname ".
                " from docparmst dp, dochdrmst dh, customermst c ".
                " where dp.cny# = dh.cny# and dp.record# = dh.docparkey ".
                " and dh.cny# = c.cny# and dh.custentity = c.entity and dh.cny# = :1 ";

            $stmt = PrepINClauseStmt($stmt, $selectedDocID, " and dh.docid ");
            $stmt[0] .= " order by dh.custentity, dh.docid, dh.whencreated ";

            $this->rename = I18N::getSingleToken('IA.CUSTOMER');
        }

        $result = QueryResult($stmt);

        XACT_COMMIT("OEPrintHandler::preBuildDocuments");

        //Map the customer/vendor entity with Doc ID.
        foreach ( $result as $row) {
            $row['WHENDUE'] = FormatDateForDisplay($row['WHENDUE']);
            if ($this->mod == 'po') {
                $row['DOCPARCLASS'] = $row['DOCCLASS'];
                $row['DOCPARID'] = $row['DOCTYPE'];
                $row['CATEGORY'] = $row['DOCTYPE'];
                $row['CUSTVENDID'] = $row['ENTITYID'];
                $row['CUSTVENDNAME'] = $row['CUSTNAME'];
                $row['VENDREC'] = $row['ENTITYID'];
                $row['DRILLDOWNKEY'] = $row['DOCTYPE'];
            }
            $this->custentityCache[$row['DOCID']] = $row;
        }
    }

    /**
     * Mark the document as printed
     *
     * @param int $key  the document key
     *
     * @return bool  true if success and false otherwise
     *
     * @see EmailPrintHandler::markDocumentAsPrinted()
     */
    protected function markDocumentAsPrinted($key)
    {
        $docValues = $this->custentityCache[$key];
        // to not upset existing behaviour we added this pref check
        $markDraft = (GetPreferenceForProperty(Globals::$g->kSOid, 'DONOT_MARK_DRAFT') == 'T') ? false : true ;
        if ($docValues['STATE'] != 'Draft' || $markDraft) {
            // Only mark as printed when this document is not in draft state
            /** @var DocumentManager $docMgr*/
            $docMgr = Globals::$g->gManagerFactory->getManager('document');
            return $docMgr->markDocumentAsPrinted($key);
        }
        return true;
    }

    /**
     * Generate the message for emailing the document
     *
     * @param int     $key         the document key
     * @param string  $entityname  the entity name
     *
     * @return string the message
     *
     * @see EmailPrintHandler::generateEmailMessage()
     */
    protected function generateEmailMessage($key, $entityname)
    {
        $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');
        $msg = $emailTokenObj->applyPlaceholders('body.text10',[
            'WHENDUE' => $this->custentityCache[$key]['WHENDUE'],
            'DOCNO' => $key
        ]);

        return $msg;
    }

    /**
     * Generate the subject for emailing the document
     *
     * @param int     $key         the document key
     * @param string  $entityname  the entity name
     *
     * @return string  the subject
     *
     * @see EmailPrintHandler::generateEmailSubject()
     */
    protected function generateEmailSubject($key, $entityname)
    {
        $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');
        return $emailTokenObj->applyPlaceholders('subject.text4', [
            'WHENDUE' => $this->custentityCache[$key]['WHENDUE'],
            'CUSTNAME' => $this->custentityCache[$key]['CUSTNAME'],
            'ENTITYNAME' => $entityname
        ]);
    }

    /**
     * @param int    $key
     * @param string $docType
     * @param string $xslformat
     * @param string $entityid
     * @param string $docclass
     *
     * @return array
     */
    protected function getTemplateType($key, $docType, $xslformat, $entityid, $docclass)
    {
        $indexKey = $docType . '#~#' . $entityid . '#~#' . $docclass;
        if ( !isset($this->templateCache[$indexKey]) ) {
            /** @var DocumentEditor $docEditor */
            $docEditor =  $this->getEditor($docType);
            $this->templateCache[$indexKey] = $docEditor->GetTemplateType($key, $docType, $xslformat, $entityid, $docclass);
        }

        return $this->templateCache[$indexKey];
    }

    /**
     * Sets PO document details record#
     *
     * @param string $docid
     * @param string $deliverylog_key
     * @param array $emailData
     */
    protected function addEmailDeliveryLogAttributes($docid, $deliverylog_key, &$emailData)
    {
        if ($this->mod == 'po') {
            $emailData['deliverylog_additional_attributes'] .= ',MODULEID';
            $emailData['deliverylog_additional_attribute_values']['MODULEID'] = GetModuleID($this->mod);

            $emailData['deliverylog_additional_attributes'] .= ',DELIVERYLOGKEY';
            $emailData['deliverylog_additional_attribute_values']['DELIVERYLOGKEY'] = $deliverylog_key;

            // PO specific attributes added
            $emailData['deliverylog_additional_attributes'] .= ',VENDORKEY';
            $emailData['deliverylog_additional_attribute_values']['VENDORKEY']
                = $this->custentityCache[$docid]['ENTITYID'];

            $emailData['deliverylog_additional_attributes'] .= ',DRILLDOWNKEY';
            $emailData['deliverylog_additional_attribute_values']['DRILLDOWNKEY']
                = $this->custentityCache[$docid]['DOCID'];

            $emailData['deliverylog_additional_attributes'] .= ',CATEGORYTYPE';
            $emailData['deliverylog_additional_attribute_values']['CATEGORYTYPE']
                = $this->custentityCache[$docid]['STATE'];

            $emailData['deliverylog_additional_attributes'] .= ',DOCUMENTDATE';
            $emailData['deliverylog_additional_attribute_values']['DOCUMENTDATE']
                = $this->custentityCache[$docid]['WHENDUE'];

            $emailData['deliverylog_additional_attributes'] .= ',ENTITYID';
            $emailData['deliverylog_additional_attribute_values']['ENTITYID']
                = $this->custentityCache[$docid]['CUSTVENDID'];

            $emailData['deliverylog_additional_attributes'] .= ',CATEGORY';
            $emailData['deliverylog_additional_attribute_values']['CATEGORY']
                = $this->custentityCache[$docid]['DOCPARID'];

            if (IsMultiEntityCompany() && GetContextLocation()) {
                $emailData['deliverylog_additional_attributes'] .= ',LOCATIONKEY';
                $emailData['deliverylog_additional_attribute_values']['LOCATIONKEY'] = GetContextLocation();
            }
        }
    }

    /**
     * @return array[]
     */
    protected function getEmailTemplates()
    {
        if (!isset($this->emailTemplateCache)) {
            $this->emailTemplateCache = [];
            /** @var EmailTemplateManager $emailTemplateMgr */
            $emailTemplateMgr = Globals::$g->gManagerFactory->getManager('emailtemplate');

            foreach ($this->emailtemplate as $docid => $emailTemplateID) {
                if (isset($this->emailDocIds[$docid]) && !isset($this->emailTemplateCache[$emailTemplateID])) {
                    $this->emailTemplateCache[$emailTemplateID] = $emailTemplateMgr->Get($emailTemplateID);
                }
            }
        }
        return $this->emailTemplateCache;
    }

}
