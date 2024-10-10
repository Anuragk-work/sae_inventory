<?php

/**
 * This is the handler to print and email SO/PO/Inventory documents
 *
 * @author    Tony Rondonuwu
 * @copyright 2014 Intacct Corporation, All Rights Reserved
 */

abstract class DocumentPrintHandler extends EmailPrintHandler
{
    /** @var array[] $emailTemplateCache */
    protected $emailTemplateCache;

    /** @var Injector $injector */
    private $injector;

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
     * Return the document type
     * 
     * @param int $key  the record key
     * 
     * @return string  the document type
     *
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
     */
    protected function getXSLTemplate($key, $docType, $xslformat)
    {
        /** @var DocumentEditor|DocumentFormEditor $docEditor*/
        $docEditor = $this->getEditor($docType);
        $xsl = $docEditor->GetXSLTemplate($key, $docType, $xslformat, []);
        return $xsl;
    }

    /**
     * Retrieve the xml representation of the record
     *  
     * @param int $key  the record key
     * 
     * @return string
     * 
     * @see EmailPrintHandler::getIndividualXML()
     */
    protected function getIndividualXML($key)
    {
        $docValues = $this->custentityCache[$key];

        $params = [
            'ENTITYID'      => $docValues['ENTITYID'],
            'DOCCLASS'      => $docValues['DOCCLASS'],
            'DOCPARID'      => $docValues['DOCTYPE'],
            'DOCID'         => $key,
            'xsltemplateid' => $this->xslformat,
            'agingOn'       => $this->agingOn,
        ];

        $editor = $this->getEditor($docValues['DOCTYPE']);
        if ( $editor instanceof FormEditor) {
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
     * @param string $xml  the record in xml format
     * @param string $xsl  the xsl template
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
                'INV-0104',
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
            /** @var DocumentEditor $docEditor*/
            $docEditor = $this->getEditor($docType);
            $this->templateCache[$indexKey] = $docEditor->GetTemplateType($key, $docType, $xslformat, $entityid, $docclass);
        }

        return $this->templateCache[$indexKey];
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

    /**
     * @param int $key
     *
     * @return array|null
     */
    protected function getEmailTemplate($key)
    {
        $retval = null;
        if (isset($this->emailtemplate[$key])) {
            $emailTemplateID = $this->emailtemplate[$key];
            $emailTemplates = $this->getEmailTemplates();
            if (isset($emailTemplates[$emailTemplateID])) {
                $retval = $emailTemplates[$emailTemplateID];
            }
        }
        return $retval;
    }

    /**
     * @param   int     $key
     * @param   string   $element
     *
     * @return null|string
     */
    protected function getEmailTemplateElement($key, $element)
    {
        $retval = null;
        $emailTemplate = $this->getEmailTemplate($key);
        if (isset($emailTemplate[$element])) {
            $injector = $this->getInjector();
            $obj = $this->custentityCache[$key];
            $retval = $injector->inject($emailTemplate[$element], $obj);
        }
        return $retval;
    }

    /**
     * @return Injector
     */
    protected function getInjector()
    {
        if (!isset($this->injector)) {
            $this->injector = new Injector();
        }
        return $this->injector;
    }
}
