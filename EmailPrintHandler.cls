<?php
/**
 *    This is the factory class for print handlers
 *
 *    @author    Valer Crisan <vcrisan@intacct.com>
 *    @copyright 2011 Intacct Corporation, All Rights Reserved
 */

import('EntityManager');
import('DocumentEditor');
require_once 'backend_delivery.inc';
require_once 'backend_pdf.inc';
require_once 'EmailPrintHandlerFactory.cls';

/**
 * Base, abstract class for print handlers.
 *
 * @author vcrisan
 */
abstract class EmailPrintHandler
{
    const CUTOFF_NOOFDOCS = 50;
    
    // This can be overriten from child classed and is using late static bindings
    /** @var int $defaultMaxCustomDocsInPDF */
    public static int $defaultMaxCustomDocsInPDF = 100;
    
    // This can be overriten from child classed and is using late static bindings
    // It is used in conjunction with feature flag: MAXIMIZE_CUSTOM_DOCUMENTS_IN_PDF
    /** @var int $maxCustomDocsInPDF */
    public static int $maxCustomDocsInPDF = 100;

    //params passed from the caller
    /** @var array $printDocIds */
    protected $printDocIds;

    /** @var array $emailDocIds */
    protected $emailDocIds;

    /** @var int $op  */
    protected $op;

    /** @var int $threshHold */
    protected $threshHold;

    /** @var bool  $checkThreshHold*/
    protected $checkThreshHold = false;

    /** @var string $mod */
    protected $mod;

    /** @var string $entity */
    protected $entity;

    /** @var string $sendersname */
    protected $sendersname;

    /** @var string $sendersemail */
    protected $sendersemail;

    /** @var bool $prevprint */
    protected $prevprint;

    /** @var bool $unpaid */
    protected $unpaid;

    /** @var string $xslformat */
    protected $xslformat;

    /** @var string $sendersphone */
    protected $sendersphone;

    /** @var string[] $custemail */
    protected $custemail;

    /** @var string[] $custbccemail */
    protected $custbccemail;

    /** @var string[] $deliveryLogKeys; */
    protected $deliveryLogKeys;

    /** @var  array $printEmailDeliveryLogKeys */
    protected $printEmailDeliveryLogKeys;

    /** @var string[] $emailSubject */
    protected $emailSubject;

    /** @var string[] $emailMsg */
    protected $emailMsg;

    /** @var  string $rename */
    protected $rename;

    /** @var string[] $emailtemplate */
    protected $emailtemplate;

    /** @var array $emailTemplateCache */
    protected $emailTemplateCache;

    /** @var string[] $custccemail */
    protected  $custccemail =array();

    // TODO: Remove $_from and $_reply_to once emailUnsentDocs is fixed.
    /**
     * @var string $_from
     */
    var $_from ='';
    /**
     * @var string $_reply_to
     */
    var $_reply_to='';

    /**
     * cache to store the xml and other data for an individual doc.
     * So that we don't have to retrieve it both for print and email.
     */
    /** @var  array $custentityCache */
    protected $custentityCache;

    /** @var  string $menuName */
    protected $menuName;

    /** @var  string $jsFunctionName */
    protected $jsFunctionName;

    /** @var Editor[]|FormEditor[] $editors */
    protected $editors = array();

    /** @var string $arInvFormat */
    protected $arInvFormat;

    /** @var string $arMessage */
    protected $arMessage;

    /** @var string $arMktText */
    protected $arMktText;

    /** @var string $agingOn */
    protected $agingOn;

    /* @var  array $templateCache */
    protected $templateCache;

    /* @var array $templateCacheByID */
    protected $templateCacheByID;

    /** @var string $htmlString */
    public $htmlString = '';

    /** @var  Dictionary $dict */
    private $dict;

    /** @var Lock[] $locks */
    private $locks = [];

    /** @var bool $genPDFForAPI */
    protected $genPDFForAPI = false; //Used to generate PDF when calling from API retrievePDF

    /** @var string $pdfDataForAPI */
    protected $pdfDataForAPI = null; //Used to hold the generated PDF data if the $genPDFForAPI is true

    /** @var bool $canInsertIntoDeliveryLog */
    protected $canInsertIntoDeliveryLog = true; // used to insert into delivery log table

    /** @var string $deliveryLogObject */
    private $deliveryLogObject = 'invoice'; // used to hold the object value for delivery log table

    /** @var string $deliveryLogDescription */
    private $deliveryLogDescription = 'OE'; // used to hold the description for delivery log table

    /** @var bool $smartEventsAttachEmail */
    private $smartEventsAttachEmail = false; // used to set true if flow is comming from smart event attach email

    /**
     * used to check for AR config PREVIEW_IS_PRINTED, if its set true, will validate with AR config else it will update the state to P
     * @var bool $printedFlagValidateWithConfig
     */
    private $printedFlagValidateWithConfig = true;


    /**
     * @param bool $genPDFForAPI
     */
    public function setPDFDataToReturn(bool $genPDFForAPI): void
    {
        $this->genPDFForAPI = $genPDFForAPI;
    }

    /**
     * Return the PDF data generated for API type
     *
     * @return string the generated PDF data buffer for API
     *
     */
    public function GetPDFDataForAPI()
    {
        return $this->pdfDataForAPI;
    }

    /**
     * Return the document type
     *
     * @param int $key  the record key
     *
     * @return string  the document type
     */
    abstract protected function getDocumentType($key);

    /**
     * Return the XSL template for this record and document type
     *
     * @param int       $key        the record key
     * @param string    $docType    the document type
     * @param string    $xslformat  xsl format override
     *
     * @return string   the xsl document template
     */
    abstract protected function getXSLTemplate($key, $docType, $xslformat);

    /**
     * Retrieve the xml representation of the record
     *
     * @param int $key  the record key
     *
     * @return string  the xml representation of the record
     */
    abstract protected function getIndividualXML($key);

    /**
     * Retrieve the FOP xml representation of the record
     *
     * @param int       $xml  the record in xml format
     * @param string    $xsl  the xsl template
     *
     * @return array  the FOP xml representation of the record
     */
    abstract protected function getFO($xml, $xsl);

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
    abstract protected function preBuildDocuments();

    /**
     * Return the template type for this record and document type
     * @param int               $key
     * @param array|bool|string $docType
     * @param string            $xslformat
     * @param string            $entityid
     * @param string            $docclass
     *
     * @return array
     */
    abstract protected function getTemplateType($key, $docType, $xslformat, $entityid, $docclass);

    /**
     * Retrieve the XML for pritning from the editor instance
     *
     * @param int $key          the key of the record to print
     * @param bool $isCustomDoc true if the request is for a custom doc
     *
     * @return string the xml
     */
    abstract protected function getXMLForPrinting($key, $isCustomDoc);

    /** @var Injector $_userPrefDateformat */
    private $_userPrefDateformat;

    /**
     * @param array $params
     */
    public function __construct($params)
    {
        $this->printDocIds = $params['docidforprint'] ?? [];
        $this->emailDocIds = $params['docidforemail'] ?? [];
        $this->op = $params['op'];
        $this->threshHold = $params['printdocthreshhold'];
        $this->mod = $params['mod'];
        $this->entity = $params['entity'];
        $this->sendersname = $params['sendersname'];
        $this->sendersemail = $params['sendersemail'];
        $this->xslformat = $params['xslformat'];
        $this->sendersphone = $params['sendersphone'];
        $this->emailtemplate = $params['emailtemplate'];
        $this->custemail = $params['custemail'];
        $this->custccemail = $params['custccemail'];
        $this->custbccemail = $params['custbccemail'];
        $this->arInvFormat = $params['arInvFormat'];
        $this->arMessage = $params['arMessage'];
        $this->arMktText = $params['arMktText'];
        $this->agingOn = $params['agingOn'];
        $this->prevprint = $params['prevprint'];
        $this->unpaid = $params['unpaid'];
        if (!isNullOrBlank($params['genPDFForAPI'])) {
            $this->setPDFDataToReturn($params['genPDFForAPI']);
        }

        // to make InvoiceEditor work we need to set this in the request:
        if ( ! $this->arInvFormat ) {
            $this->arInvFormat = GetMyInvoiceFormat();
        }

        $this->deliveryLogKeys = $params['deliveryLogKeys'];
        $this->emailSubject = $params['emailSubject'];
        $this->emailMsg = $params['emailMsg'];

        Request::$r->_invformat = $this->arInvFormat;

        $this->_userPrefDateformat = $params['userprefdateformat'];

    }

    /**
     * Instantiate (or retrieve from cache) the approriate editor class depending on the document type
     *
     * @param string $doctype
     *
     * @return Editor|FormEditor
     */
    protected function getEditor($doctype)
    {
        if (!array_key_exists($doctype, $this->editors)) {
            Request::$r->_dt = $doctype;
            $this->editors[$doctype] = GetEntityEditor($this->entity);
        }
        return $this->editors[$doctype];
    }

    /**
     * Retrieve the AR invoice format
     *
     * @return string  the ar invoice format
     */
    protected function getARInvoiceFormat()
    {
        return $this->arInvFormat;
    }

    /**
     * Mark the document as printed
     *
     * @param int $key  the document key
     *
     * @return bool  true if success and false otherwise
     */
    abstract protected function markDocumentAsPrinted($key);

    /**
     * Generate the message for emailing the document
     *
     * @param int       $key         the document key
     * @param string    $entityname  the entity name
     *
     * @return string  the message
     */
    abstract protected function generateEmailMessage($key, $entityname);

    /**
     * Generate the subject for emailing the document
     *
     * @param int       $key         the document key
     * @param string    $entityname  the entity name
     *
     * @return string  the subject
     */
    abstract protected function generateEmailSubject($key, $entityname);

    /**
     * Generate the signature for emailing the document
     *
     * @return string  the signature
     */
    protected function generateEmailSignature()
    {
        return GetMyCompanyName() . " (" . $this->sendersemail . ")";
    }

    /**
     * Generate the document name for the email attachment
     *
     * @param int $key  the document key
     *
     * @return string  the document name
     */
    protected function generateEmailDocName($key)
    {
        return (string)$key;
    }
    /**
     * Set the menu name.
     *
     * @param string $menuName  the name of the menu
     */
    protected function setMenuName($menuName)
    {
        $this->menuName = $menuName;
    }

    /**
     * Set the entity name
     *
     * @param string $entity  the entity name
     */
    protected function setEntity($entity)
    {
        $this->entity = $entity;
    }

    /**
     * Set the name of the JS function to invoke when delivering the PDF.
     * It will be called by the child handler classes to set the js function,
     * which will be used to determine the launch function type
     *
     * @param string $functionName  the JS function name
     */
    protected function setJSFunctionName($functionName)
    {
        $this->jsFunctionName = $functionName;
    }

    /**
     * @param string[] $printandEmailDocs
     *
     * @return bool
     */
    public function hasAlreadyPrintedEmailedDocs($printandEmailDocs)
    {
        $alreadyPrintedEmailed = false;
        if (count($printandEmailDocs) > 0) {
            $stmt = [];
            if($this->mod == 'ar') {
                $stmt[0] = "select count(1) CNT  from prrecord prrec where prrec.cny#=:1 and prrec.state = 'P'";
                $inClause = " and prrec.record#";
            } else {
                $stmt[0] = "select count(1) CNT  from dochdrmst dochdr where dochdr.cny#=:1 and dochdr.printed = 'T'";
                $inClause = " and dochdr.docid";
            }

            $stmt[1] = GetMyCompany();
            $stmt = PrepINClauseStmt($stmt, array_unique(array_keys($printandEmailDocs)), $inClause);
            $result = QueryResult($stmt);
            if($result[0]['CNT'] > 0) {
                $alreadyPrintedEmailed = true;
                $this->warnInvoiceStatus();
            }
        }

        return $alreadyPrintedEmailed;
    }

    protected function warnInvoiceStatus()
    {
        $this->htmlString .= "<script type='text/javascript'>warnstatus();</script>";
    }

    /**
     * @param string $lockName
     *
     * @return bool
     */
    protected function acquireDocumentLock($lockName)
    {
        $editlock = new Lock();
        if (!$editlock->setLock($lockName, 10800, false)) {
            $this->warnInvoiceStatus();
            return false;
        }
        $this->locks[$lockName] = $editlock;

        return true;
    }

    /**
     * @return bool
     */
    protected function removeDocumentLock()
    {
        foreach ($this->locks as $lockName => $lockval) {
            $this->locks[$lockName]->releaseLock();
        }

        return true;
    }


    /**
     * Handle the print and email functions.
     *
     * @param int   &$attachmentCount  the attachment count
     * @param bool  $isOffline         flag to determine if the process is offline or not
     *
     * @return bool  true if success, false otherwise
     */
    public function doPrintAndEmail(&$attachmentCount, $isOffline)
    {
        $ok = true;
        if (count($this->printDocIds ?? []) == 0 && count($this->emailDocIds ?? []) == 0) {
            $gErr = Globals::$g->gErr;
            $gErr->addIAError(
                'INV-0109',
                __FILE__ . __LINE__,
                "There are no documents selected for Print/Email",
                [],
                '',
                [],
                "Please select atleast one document for Print/Email",
                []
            );
            return false;
        }

        //retrieve and build cache for all documents for email or print
        $this->preBuildDocuments();

        // initialize the html ctrol string
        $this->htmlString = '';

        if ($this->prevprint === 'false') {
            $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');
            // Checks documents are printed or not (false - not printed, true - printed)
            $ok = $ok && !$this->hasAlreadyPrintedEmailedDocs($this->printDocIds);
            // Checks documents are emailed or not (false - not emailed, true - emailed)
            $ok = $ok && !$this->hasAlreadyPrintedEmailedDocs($this->emailDocIds);
            if (!$ok && $isOffline) {
                $msg = $emailTokenObj->applyPlaceholders('body.text',[]);
                $this->sendEmail($msg, false);
                Globals::$g->gErr->addIAError('INV-0110', __FILE__ . ":" . __LINE__,
                 "Some of the selected invoices has been delivered. Please reload and select
                 the reports again to print.",
                 []
                );
            }
        }

        //handle print document
        if ($this->printDocIds) {
            $ok = $ok && $this->doPrintDocuments($attachmentCount, $isOffline);
        }

        //handle emails
        if ($this->emailDocIds) {
            $ok = $ok && $this->doEmailDocuments($isOffline);
        }
        $this->removeDocumentLock();

        return $ok;
    }

    /**
     * @param string $msg
     * @param bool $subject
     *
     * @return bool
     */
    private function sendEmail($msg, $subject)
    {
        $mailTo = $this->sendersname . " <" . $this->sendersemail . ">";
        $mailFrom = 'Intacct Customer Support <noreply@intacct.com>';
        $isSuccessMsg = $subject ? I18N::getSingleToken('IA.SUCCESSFUL') : I18N::getSingleToken('IA.FAILED');
        $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');
        $subjectMsg = $emailTokenObj->applyPlaceholders('subject.text', [
            'ISSUCCESSMSG' => $isSuccessMsg
        ]);
        $emailData = array(
            'mailto' => $mailTo,
            'from' => $mailFrom,
            'replyto' => $mailFrom,
            'subject' => $subjectMsg,
            'message' => $msg,
            'contenttype' => I18N::isMarkdown($emailTokenObj->getEmailTokenName() . '.' . I18NEmail::TOKEN_SUFFIX_WITH_MARKDOWN)
                ? 'text/html; charset="' . isl_get_charset() . '"'
                : 'text/plain; charset="' . isl_get_charset() . '"',
        );

        $publish = new ims_publish('InvoiceOfflinePrintingFailure', 'EMAIL', 'SEND_EMAIL', '', $emailData);
        if (!$publish->PublishNonblocking($res)) {
            Globals::$g->gErr->addIAError(
                'INV-0111',
                __FILE__ . '.' . __LINE__,
                'Unable to publish the message. ',
                [],
                'Check your function arguments to make sure correct values have been specified.',
                []
            );
            return false;
        }

        return true;
    }

    /**
     * Prepare the print operation.
     *
     * @param int   &$attachmentCount  a reference variable which will return the number of records processed
     * @param bool  $isOffline         if the process is to be performed online or offline
     *
     * @return bool  true if success, false otherwise
     */
    private function doPrintDocuments(&$attachmentCount, $isOffline)
    {
        $xmlByDocType = array();
        $xmlArrayByDocType = array(); // for grouping a predefined number of document together for each document type.
        $countByDocType = array();
        $attachmentCount = 0;
        $elementcnt = [];
        $batchidx = [];

        // get max number of custom documents system can handle inside sinlge PDF
        // the same value should be used for max nr of items within a batch
        $cuttoffNoOfDocs = $this->getMaxCustomDocsInPDF();

        // set the delivery method to return the dataxml
        Request::$r->_deliverymethod = 'xmldataraw';

        $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');
        // they want to print some documents
        foreach ($this->printDocIds as $key => $value) {
            // Checking whether document is already printed or not
            $uniqueLockKey = GetMyCompany() . '_PRINTDOCUMENT_' . $key;
            if ($this->prevprint === 'false') {
                if (!$this->acquireDocumentLock($uniqueLockKey)) {
                    if ($isOffline) {
                        $msg = $emailTokenObj->applyPlaceholders('body.text1',[]);
                        $this->sendEmail($msg, false);
                        Globals::$g->gErr->addIAError('INV-0112', __FILE__ . ":" . __LINE__,
                         "Some of the invoices selected are locked and being processed.
                         Please reload and select the reports again to print.",
                         []
                        );
                    }
                    return false;
                }
            }
            // set _r so the editor knows which we are working on
            Request::$r->_r = $key;

            $docValues = $this->getDocumentType($key);

            if ( is_array($docValues) ) {
                $docType = $docValues['DOCTYPE'];
                $entityid = $docValues['ENTITYID'];
                $docclass = $docValues['DOCCLASS'];
            }

            /** @noinspection PhpUndefinedVariableInspection */
            $currentTemplate = $this->getTemplateType($key, $docType, $this->xslformat, $entityid, $docclass);
            $this->templateCacheByID[$currentTemplate['DESCRIPTION']] = $currentTemplate;
            $isCustomDoc = ( $currentTemplate['type']=='DOC' || $currentTemplate['type']=='DOX' ? true : false );
            $individualxml = $this->getIndividualXML($key);

            if ( HasErrors() ) {
                return false;
            }

            // create a key for caching XML
            $xmlCacheKey = $docType . ( $isCustomDoc ? '#~#'.$currentTemplate['DESCRIPTION'] : '' );
            $elementcnt[$xmlCacheKey]++;
            if(!isset($batchidx[$xmlCacheKey])){
                $batchidx[$xmlCacheKey] = 0;
            }
            //initialize the tracking for each document type
            if (!isset($xmlByDocType[$xmlCacheKey])) {
                $xmlByDocType[$xmlCacheKey] = array();
                $countByDocType[$xmlCacheKey] = 0;
                $xmlArrayByDocType[$xmlCacheKey] = array();
            }

            if ( $isCustomDoc ) {
                if ( $cuttoffNoOfDocs > 0 && $elementcnt[$xmlCacheKey] > $cuttoffNoOfDocs ) {
                    $batchidx[$xmlCacheKey]++;
                    $elementcnt[$xmlCacheKey] = 1;
                    // intialize the XML string for the current batch
                    $xmlByDocType[$xmlCacheKey][$batchidx[$xmlCacheKey]] = array();
                }
                // render pdf from doc/docx template
                // to check whether same record is selected for email also
                if (isset($this->emailDocIds[$key])) {
                    $this->custentityCache[$key]['xml'] = $individualxml;
                }

                // pick up document section
                $start = isl_strpos($individualxml, '<Merge xmlns="http://www.intacct.com/">') + 52;
                $end = isl_strpos($individualxml, '</document>') + 11;
                $individualxml = isl_substr($individualxml, $start, $end - $start);

                $xmlByDocType[$xmlCacheKey][$batchidx[$xmlCacheKey]][] = $individualxml;

                //Generate the XML
                $dataXML = $this->getXMLForPrinting($key, true);


                list($langCode, $countryCode) = explode('-', $currentTemplate['LOCALE']);
                $langCode = ( $langCode != '' ? $langCode : 'en' );
                $countryCode = ( $countryCode != '' ? $countryCode : 'US' );

                $pdfParams = array(
                    'LANGCODE' => $langCode,
                    'COUNTRYCODE' => $countryCode,
                    'WHENMODIFIED' => $currentTemplate['WHENMODIFIED'],
                    'ENCRYPTPDF' => $currentTemplate['ENCRYPTPDF'],
                );

                // generate PDF data to store it in the delivery log
                $blobdata = genPDFFromWORD($dataXML, $currentTemplate['template'], false, $pdfParams);

            } else {
                $xsl = $this->getXSLTemplate($key, $docType, $this->xslformat);
                $data = $this->getFO($individualxml, $xsl);
                $xmlByDocType[$xmlCacheKey][$key] .= $data['xml'];
                $this->custentityCache[$key]['fo'] = $data['fo'];
                $blobdata = $data['fo'];
            }

            $ok = true;
            $attachments = null;
            $deliveryOptions = 'P';
            // to check whether same record is selected for email also
            if (isset($this->emailDocIds[$key])) {
                $deliveryOptions = 'P#E';
            }
            $deliverylog = $this->addIntoDeliveryLog(
                $key, $blobdata, $attachments,
                $deliveryOptions
            );

            // Remember delivery log key so that when its time for emailing we have access to it
            if (isset($this->emailDocIds[$key])) {
                if (!isset($this->printEmailDeliveryLogKeys)) {
                    $this->printEmailDeliveryLogKeys = [];
                }

                $this->printEmailDeliveryLogKeys[$key] = $deliverylog['RECORDNO'];
            }

            if (!$ok) {
                Globals::$g->gErr->addIAError('INV-0113', __FILE__ . __LINE__,
                    "Error in logging delivered invoices.",
                    []
                );
            }

            // show that we've delivered the doc
            $ok = $ok && $this->markDocumentAsPrinted($key);

            if ( !$ok ) {
                return false;
            }

            $countByDocType[$xmlCacheKey]++;
            if ($countByDocType[$xmlCacheKey] == $this->threshHold && $this->checkThreshHold) {
                $xmlArrayByDocType[$xmlCacheKey][] = $xmlByDocType[$xmlCacheKey];
                $xmlByDocType[$xmlCacheKey] = array('');
                $countByDocType[$xmlCacheKey] = 0;
                $attachmentCount++;

                // reset the batch count and element count since we split the attachment
                $batchidx[$xmlCacheKey] = 0;
            }
        }
        //end of for each document to be printed.

        //putting the leftover at the end of the array for each doctype
        foreach ($countByDocType as $idx => $count) {
            if ($count != 0) {
                $xmlArrayByDocType[$idx][] = $xmlByDocType[$idx];
                $attachmentCount++;
            }
        }

        return $this->printDocument($xmlArrayByDocType, $isOffline);
    }

    /**
     * Handles the print operation; called by printDocument()
     * you should never need to call this API independently
     *
     * @param array     $xmlArrayByDocType   this array has all the data about the documents selected for print/email;
     * @param bool      $isOffline           flag to idicate if we're online or offline mode
     *
     * @return bool true on success, false on failure
     */
    private function printDocument(&$xmlArrayByDocType, $isOffline)
    {
        $gErr = Globals::$g->gErr;
        $gManagerFactory = Globals::$g->gManagerFactory;
        $deliveryhistoryMgr = $gManagerFactory->getManager('deliveryhistory');
        $maxDocsInPDF = $this->getMaxCustomDocsInPDF();
        
        $count = 1;

        import('GroupReporter');
        $tempDelivery = array(
            'OBJECT' => 'doc_temp',
            'DELIVERYOPTIONS' => "P",
            'ENTITY' => "CTEMP",
        );

        foreach ($xmlArrayByDocType as $xmlCacheKey => $xmlArray)
        {

            list($docType, $templateID) = explode('#~#', $xmlCacheKey);
            $fileNamePrefix = "Attachment_" . $docType . "_";

            $isCustomDoc = false;
            $currentTemplate = $pdfParams = array();

            //Get the template used for doc type
            if ( isset($this->templateCacheByID[$templateID]) ) {
                $currentTemplate = $this->templateCacheByID[$templateID];
                $isCustomDoc = ( $currentTemplate['type']=='DOC' || $currentTemplate['type']=='DOX' ? true : false );

                list($langCode, $countryCode) = explode('-', $currentTemplate['LOCALE']);
                $langCode = ( $langCode != '' ? $langCode : 'en' );
                $countryCode = ( $countryCode != '' ? $countryCode : 'US' );

                $pdfParams = array(
                    'LANGCODE' => $langCode,
                    'COUNTRYCODE' => $countryCode,
                    'WHENMODIFIED' => $currentTemplate['WHENMODIFIED'],
                    'ENCRYPTPDF' => $currentTemplate['ENCRYPTPDF'],
                );
            }

            foreach ($xmlArray as $xmlArr) {
                $tmpout = array();
                // let's process the batch here, the result is an array of PDFs/XMLs in $tmpout
                foreach ($xmlArr as $docId => $xmls) {
                    if ( $isCustomDoc ) {
                        $header_xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<soap12:Envelope xmlns:xsi=\""
                            . "http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\""
                            . "http://www.w3.org/2001/XMLSchema\" xmlns:soap12=\"http://www.w3.org/2003/05/"
                            . "soap-envelope\">\n<soap12:Body>\n<Merge xmlns=\"http://www.intacct.com/\">"
                            . "\n<documents>\n";

                        $footer_xml = "\n</documents>\n</Merge>\n</soap12:Body>\n</soap12:Envelope>\n";
                        $combined_xml = '';

                        $totalXmls = count($xmls);
                        
                        foreach ($xmls as $idx => $xml) {
                            // render pdf from doc/docx template
                            $combined_xml .= $xml;

                            if ($idx == ($totalXmls-1) || ($idx+1)%$maxDocsInPDF == 0) {
                                $combined_xml = $header_xml . $combined_xml . $footer_xml;

                                $pdfdata = genPDFFromWORD($combined_xml, $currentTemplate['template'], false,
                                    $pdfParams);

                                if (!$pdfdata) {
                                    $gErr->addIAError('INV-0114', __FILE__ . __LINE__,
                                        "Error in printing documents.",
                                        []
                                    );
                                    return false;
                                }

                                $tmpout[] = $pdfdata;

                                // Get and store result only if call from API
                                if ($this->genPDFForAPI) {
                                    $this->pdfDataForAPI = $pdfdata;
                                    return true;
                                }

                                $combined_xml = '';
                            }
                        }

                    } else {
                        // if we are not dealing with the DOC type, we simply build an array of all XMLs
                        // the array will be later joined together and passed to the XSLT to build the FO
                        $tmpout[] = $this->custentityCache[$docId]['fo'];
                    }
                }

                if ( $isCustomDoc ) {
                    //display the pdf directly in the browser
                    if (!$isOffline) {
                        //throw out the pdfs one by one in separate windows
                        // (for e.g, for 1000 docs to print and a limit of 50, it will open 20 windows)
                        foreach ($tmpout as $out) {
                            $tempDelivery['RECORDNO'] = '';
                            $tempDelivery['XML'] = $out;
                            $ok = $deliveryhistoryMgr->add($tempDelivery);
                            if (!$ok) {
                                $gErr->addIAError('INV-0115', __FILE__ . __LINE__,
                                    "Error in printing documents.",
                                    []
                                );
                                return false;
                            }

                            $count++;

                            //call a javascript function to launch document.phtml and pass a unique parameter.
                            //check for that parm in document.phtml if present fetch and display pdf.
                            $this->makePDFViewString($tempDelivery);
                        }
                    } else {
                        foreach ($tmpout as $out) {
                            $this->saveInDB($out, $docType, $fileNamePrefix . $count);
                            $count++;
                        }
                    }
                } else {
                    // we need to concatenate the XMLs from $tmpout to obtain the entire XML
                    $pdfArr = array();
                    foreach ($tmpout as $fo) {
                        $pdfArr[] = genPDF($fo, false);
                    }

                    $pdfdata = GroupReporter::concatPDFs($pdfArr, false);

                    if ( ! $pdfdata ) {
                        $gErr->addIAError('INV-0116', __FILE__ . __LINE__,
                            "Error in printing documents.",
                            []
                        );
                        return false;
                    }

                    if ($this->genPDFForAPI) {
                        // Set and store result only if call from api
                        $this->pdfDataForAPI = $pdfdata;
                        return true;
                    } else if (!$isOffline) {
                        //display the pdf directly in the browser
                        $tempDelivery['RECORDNO'] = '';
                        $tempDelivery['XML'] = $pdfdata;
                        $ok = $deliveryhistoryMgr->add($tempDelivery);
                        if (!$ok) {
                            $gErr->addIAError('INV-0117', __FILE__ . __LINE__,
                                "Error in printing documents.",
                                []
                            );
                            return false;
                        }

                        $this->makePDFViewString($tempDelivery);
                    } else {
                        //$pdfdata = genPDF($fo, false);
                        $this->saveInDB($pdfdata, $docType, $fileNamePrefix . $count);
                    }
                    $count++;
                }
            }
        }
        //end of for each xmlArrayByDocType

        //send the email notification since we have finished storing the pdf files in the offline report store
        if ($isOffline) {
            $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');
            $msg = $emailTokenObj->applyPlaceholders('body.text2', [
                'MENUNAME' => $this->menuName
            ]);
            if (!$this->sendEmail($msg, true)) {
                return false;
            }
        }

        return true;
    }

    /**
     * Add the xml data for the documents to be print/email 'ed to the database,
     * in case the type is selected as offline
     * you should never need to call this function directly
     *
     * @param string $pdfdata       the pdf data returned by genData() API
     * @param string $docType       the document type being handled
     * @param string $description   a short description about the report data
     *
     * @return bool  true on success, false on failure
     */
    private function saveInDB($pdfdata, $docType, $description)
    {
        global $gInstalledModuleIDIndex;
        $gManagerFactory = Globals::$g->gManagerFactory;

        $rptStrMgr = $gManagerFactory->getManager('reportstore');

        $modulekey = $gInstalledModuleIDIndex[$this->mod];

        //removing compression till Valer/Rich figures out why it is corrupting the PDF files
        //$pdfdata = databaseStringCompress($pdfdata);

        $reportData = array(
            'REPORTID' => $docType,
            'DESCRIPTION' => $description,
            'USERKEY' => GetMyUserid(),
            'MODULEKEY' => $modulekey,
            'PDFSTATUS' => 'C',
            'PDFDATA' => $pdfdata,
            'WHENCREATED' => gmdate('m/d/Y H:i:s', time())
        );

        $ok = $rptStrMgr->add($reportData);

        return $ok;
    }

    /**
     * @param bool $offline
     *
     * @return bool
     */
    private function doEmailDocuments($offline=false)
    {
        $gErr = Globals::$g->gErr;

        // set the delivery method to send the email
        Request::$r->_deliverymethod = 'xmldataraw';

        $unSentDocs = array();
        $ok = true;
        $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');

        foreach ( $this->emailDocIds as $key => $value) {
            $uniqueLockKey = GetMyCompany() . '_EMAILDOCUMENT_' . $key;
            if ($this->prevprint === 'false') {
                if (!$this->acquireDocumentLock($uniqueLockKey)) {
                    if ($offline) {
                        $msg = $emailTokenObj->applyPlaceholders('body.text3', []);
                        $this->sendEmail($msg, false);
                        $gErr->addIAError('INV-0118', __FILE__ . ":" . __LINE__,
                            "Some of the invoices selected are locked and being processed.
                            Please reload and select the reports again to print.",
                            []
                        );
                    }
                    return false;
                }
            }
            $ok = $this->getPDFData($key, $pdfdata, $blobdata, $unSentDocs);
            if ( !$ok ) {
                continue;
            }

            // If there is no pdf data, then don't send an email to the document recipient.
            if ( !$pdfdata ) {
                // Track the documents that are not sent so we can report (or email) the sender
                $this->addUnsentDoc($unSentDocs, $key);
                $ok = false;
                continue;
            }

            $entityname = $this->rename;

            $message = $this->getEmailMessage($key, $entityname);
            $mailFrom = $this->getMailFrom($key);

            // If there is no pdf data, then don't send an email to the document recipient.
            if ( !$pdfdata ) {
                // Track the documents that are not sent so we can report (or email) the sender
                $this->addUnsentDoc($unSentDocs, $key);
                $ok = false;
                continue;
            }

            $emailData = array(
                'mailto' => $this->custemail[$key],
                'contenttype' => 'text/html; charset="' . isl_get_charset() . '"',
                'from' => $mailFrom,
                'sendername' => $this->sendersname,
                'senderemail' => $this->sendersemail,
                'replyto' => $mailFrom,
                'subject' => $this->getEmailSubject($key, $entityname),
                'message' => $message,
                'attachments' => array(
                    '0' => array(
                        'filename' => $this->generateEmailDocName($key) . '.pdf',
                        'message' => base64_encode($pdfdata),
                        'encoding' => 'base64'
                    )
                )
            );

            $ok = $this->addAdditionalEmailData($key, $emailData);
            if ( !$ok ) {
                // Track the documents that are not sent so we can report (or email) the sender
                $this->addUnsentDoc($unSentDocs, $key);
                continue;
            }

            if ($this->custccemail[$key]) {
                $emailData['mailcc'] = $this->custccemail[$key];
            }

            if ($this->custbccemail[$key]) {
                $emailData['mailbcc'] = $this->custbccemail[$key];
            }

            XACT_BEGIN("deliverdocumentbyemail");

            // Unset value from last iteration
            $deliveryLogKey = '';

            // Save to delivery log when it is only email and if not already provided
            // If print is also requested it means delivery log is already created
            if (!isset($this->deliveryLogKeys[$key])
                && !(isset($this->printDocIds[$key]) && isset($this->printEmailDeliveryLogKeys[$key]))
            ) {
                // Mark this as printed if its not marked earlier. If the email fails, this will be rolled back.
                $this->markDocumentAsPrinted($key);
                // Save FO before sending out email, that way email delivery log can have reference to it
                $dlvrop = (!isset($this->printDocIds[$key])) ? 'E' : 'P#E';
                $deliverylog = $this->addIntoDeliveryLog(
                    $key, $blobdata,
                    $emailData['attachments'], $dlvrop
                );

                if (empty($deliverylog['RECORDNO'])) {
                    $gErr->addIAError('INV-0119', __FILE__ . __LINE__,
                        "Error in logging delivered invoices.",
                        []
                    );
                    XACT_ABORT("deliverdocumentbyemail");
                    // Track the documents that are not sent so we can report (or email) the sender
                    $this->addUnsentDoc($unSentDocs, $key);
                    $ok = false;
                    continue;
                }
                $deliveryLogKey = $deliverylog['RECORDNO'];

            } else if (isset($this->printDocIds[$key]) && isset($this->printEmailDeliveryLogKeys[$key])) {
                // Both Print and Email were requested
                // Delivery Log is created as part of Print
                // We will just attach supdoc here
                $tmp_deliverylog = null;
                $ok = $this->attachAndLogAttachments($key, $tmp_deliverylog, $emailData['attachments']);

                if (!$ok) {
                    return false;
                }

                $deliveryLogKey = $this->printEmailDeliveryLogKeys[$key];
            }

            // Resend scenario
            if ( isset($this->deliveryLogKeys[$key]) ) {
                $deliveryLogKey = $this->deliveryLogKeys[$key];

                // Retrieve attachments from delivery log
                $ok = $this->attachFromDeliveryLog($deliveryLogKey, $emailData['attachments']);
                if (!$ok) {
                    $gErr->addIAError('INV-0120', __FILE__ . __LINE__,
                        "Error retrieving attachments from delivery log.",
                        []
                    );
                    XACT_ABORT("deliverdocumentbyemail");
                    // Track the documents that are not sent so we can report (or email) the sender
                    $this->addUnsentDoc($unSentDocs, $key);
                    $ok = false;
                    continue;
                }

            }

            // Additional email delivery attributes are passed
            $this->addEmailDeliveryLogAttributes($key, $deliveryLogKey, $emailData);

            $publish = new ims_publish('DeliverInvoiceByEmail', 'EMAIL', 'SEND_EMAIL', '', $emailData);
            if (!$publish->PublishNonblocking($res)) {
                $gErr->addIAError(
                    'INV-0121',
                    __FILE__ . '.' . __LINE__,
                    'Unable to publish the message. ',
                    [],
                    'Check your function arguments to make sure correct values have been specified.',
                    []
                );
                XACT_ABORT("deliverdocumentbyemail");
                // Track the documents that are not sent so we can report (or email) the sender
                $this->addUnsentDoc($unSentDocs, $key);
                $ok = false;
                continue;
            }

            XACT_COMMIT("deliverdocumentbyemail");
        }
        // Notify the user(s) if there are unsent documents
        if ( count($unSentDocs) > 0 ) {
            $this->handleUnsentDocs($unSentDocs, $offline);
        }

        return $ok;
    }

    /**
     * @param int   $key
     * @param array $emailData
     *
     * @return bool
     */
    protected function addAdditionalEmailData(
        /** @noinspection PhpUnusedParameterInspection */ $key,
        /** @noinspection PhpUnusedParameterInspection */ &$emailData )
    {
        // Nothing by default

        return true;
    }

    /**
     * @param int   $key
     * @param array $deliverylog
     * @param array $attachments
     *
     * @return bool
     */
    protected function attachAndLogAttachments(
        /** @noinspection PhpUnusedParameterInspection */ $key,
        /** @noinspection PhpUnusedParameterInspection */ &$deliverylog,
        /** @noinspection PhpUnusedParameterInspection */ &$attachments)
    {
        return true;
    }

    /**
     * @param string    $deliveryLogKey
     * @param array     $attachments
     *
     * @return bool
     */
    protected function attachFromDeliveryLog(
        /** @noinspection PhpUnusedParameterInspection */ $deliveryLogKey,
        /** @noinspection PhpUnusedParameterInspection */ &$attachments)
    {
        return true;
    }

    /**
     * @param string    $txn_vid
     * @param string    $deliverylog_key
     * @param array     $emailData
     */
    protected function addEmailDeliveryLogAttributes( $txn_vid, $deliverylog_key, &$emailData )
    {
        // No default attributes for now
    }

    /**
     * This function returns the human readable document id
     * (useful for reporting to the intacct user when an error occurs)
     *
     * @param int|string $key  the document identifier from the for loop (might be a record# or string)
     *
     * @return string
     */
    protected function getDocID($key)
    {
        return $key;
    }

    /**
     * This function adds a document to the unsent document list to later report it to the sender
     *
     * @param array         $unSentDocs  array of unsent documents
     * @param int|string    $key         identifier of the document
     */
    private function addUnsentDoc(&$unSentDocs, $key)
    {
        $from = $this->getMailFrom($key);
        $unSentDocs[$from][] = array(
            'mailto' => $this->custemail[$key],
            'docid' => $this->getDocID($key)
        );
    }

    /**
     * This function handles unsent documents by either emailing the sender or reporting an error
     *
     * @param array $unSentDocs  array of unsent documents
     * @param bool  $offline     whether or not this is being executed offline (if offline, then email)
     */
    private function handleUnsentDocs($unSentDocs, $offline=false)
    {
        if ( $offline ) {
            $this->emailUnsentDocs($unSentDocs);
        } else {
            $errorMsg = "The following documents were not sent due to errors (documents not listed were sent): ";
            $comma = '';
            $placeholderText = '';
            $placeholder = [];
            $errorCode = 'INV-0543';
            foreach ( $unSentDocs as $docs ) {
                foreach ($docs as $data) {
                    $placeholderText .= $comma . $data['docid'];
                    $comma = ', ';
                }
            }
            $errorMsg .= $placeholderText;
            $placeholder = ['DATA_DOC_ID'=>$placeholderText];
            Globals::$g->gErr->addIAError(
                $errorCode, __FILE__ . __LINE__,
                $errorMsg, $placeholder,
                '', [],
                "Please try again or contact customer service.", []
            );
            // i18N::TODO - (Code Change Review)
        }
    }

    /**
     * This function notifies the Intacct user that certain documents were not sent
     * probably due to PDFs not being generated (Tomcat or other failure)
     *
     * @param array $unSentDocs  an array containing a list of unsent documents
     * $unSentDocs[<sender name>][] = array( 'docid' => <docid>, 'mailto' => <recipient>, 'subject' => <email subject> )
     */
    private function emailUnsentDocs($unSentDocs)
    {
        $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');

        foreach ( $unSentDocs as $sender => $docs ) {
            $message = $emailTokenObj->applyPlaceholders('body.text4', [
                'SENDER' => $sender
            ]);

            foreach ( $docs as $data ) {
                $message .= $emailTokenObj->applyPlaceholders('body.text5', [
                    'DOCID' => $data['docid'],
                    'MAILTO' => $data['mailto']
                ]);
            }
            $message .= $emailTokenObj->applyPlaceholders('body.text6', []);
            $subject = $emailTokenObj->applyPlaceholders('subject.text1', []);
            $email = new IAEmail($sender);
            $email->subject = $subject;
            // TODO: Next two lines should be $email-> ??
            $this->_from = 'Intacct Customer Support <support@intacct.com>';
            $this->_reply_to = 'support@intacct.com';
            $email->body = $message;
            $email->send();
        }
    }

    /**
     * This function accepts the deliveryObj value and calls the launch api,
     * the launch api takes care of opening the pdf view
     *
     * @param array $deliveryObj  the deliver object info
     */
    function makePDFViewString(&$deliveryObj)
    {
        $op = $this->op;
        $recordno = $deliveryObj['RECORDNO'];
        $this->htmlString .= "<script type='text/javascript'>";
        $this->htmlString .= "documentLaunch('$op', 'doc_temp', '$recordno', '');";
        $this->htmlString .= "</script>";
    }

    /**
     * @param int|string    $key
     * @param string        $entityname
     *
     * @return string
     */
    protected function generateCompleteEmailMessage($key, $entityname)
    {
        $emailTokenObj = I18NEmailToken::buildFromResource('IA.EMAIL.INV.EMAIL_PRINT_HANDLER');
        $message = $emailTokenObj->applyPlaceholders('body.text7',[
            'ENTITYNAME' => $entityname
        ]);
        $message .= $this->generateEmailMessage($key, $entityname);
        $message .= $emailTokenObj->applyPlaceholders('body.text14',[]);
        if ($this->sendersphone) {
            $message .= $emailTokenObj->applyPlaceholders('body.text15', [
                'SENDERSPHONE' => $this->sendersphone
            ]);
        } else {
            $message .= ".";
        }

        $url = "<a href='http://www.adobe.com/products/acrobat/readstep2.html'>" . strtolower(I18N::getSingleToken('IA.HERE')) . "</a>";
        $message .= $emailTokenObj->applyPlaceholders('body.text16', [
            'URL' => $url,
            'SENDERSNAME' => $this->sendersname
        ]);
        $message .= $this->generateEmailSignature();
        return $message;
    }

    /**
     * @param int|string $key
     *
     * @return string
     */
    protected function getMailFrom(/** @noinspection PhpUnusedParameterInspection */ $key)
    {
        $sendersName = $this->sendersname;
        $sendersEmail = $this->sendersemail;
        $mailFrom = $sendersName . " <" . $sendersEmail . ">";
        return $mailFrom;
    }

    /**
     * @return Dictionary
     */
    private function getDictionary()
    {
        if ( !isset($this->dict) ) {
            $this->dict = Dictionary::getInstance();
        }

        return $this->dict;
    }

    /**
     * @param int|string    $key
     * @param string        $entityname
     *
     * @return string
     */
    protected function getEmailMessage($key, $entityname)
    {
        if ( $this->emailMsg[$key] ) {
            $message = $this->emailMsg[$key];
        }
        else {
            $message = $this->generateCompleteEmailMessage($key, $entityname);
        }

        return $message;
    }

    /**
     * @param string|int    $key
     * @param array         $pdfdata
     * @param string|null   $blobdata
     * @param array         $unSentDocs
     *
     * @return bool
     */
    protected function getPDFData($key, &$pdfdata, &$blobdata, &$unSentDocs)
    {
        if ( isset($this->deliveryLogKeys[$key]) ) {
            $ok = $this->getPDFDataFromDeliveryLog($key, $this->deliveryLogKeys[$key], $pdfdata, $unSentDocs);
            $blobdata = null;
        }
        else {
            $ok = $this->generatePDFData($key, $pdfdata, $blobdata, $unSentDocs);
        }

        return $ok;
    }

    /**
     * @param int|string        $key
     * @param int|string        $deliveryLogKey
     * @param array|string|bool $pdfdata
     * @param array             $unSentDocs
     *
     * @return bool
     */

    protected function getPDFDataFromDeliveryLog( $key, $deliveryLogKey, &$pdfdata, &$unSentDocs)
    {
        $wheres['RECORD#'] = $deliveryLogKey;
        $objArr = GetDeliveryLog($wheres);
        $fo = $objArr[0]['XML'];

        if (substr($fo, 0, 4)  == '%PDF') {
            $pdfdata = $fo;
        } else {
            $pdfdata = genPDF($fo, false);
        }

        if ($pdfdata === false) {
            $this->addUnsentDoc($unSentDocs, $key);
            return false;
        }

        return true;
    }

    /**
     * @param string|int            $key
     * @param array|bool|string     $pdfdata
     * @param bool|string           $blobdata
     * @param array                 $unSentDocs
     *
     * @return bool
     */
    protected function generatePDFData($key, &$pdfdata, &$blobdata, &$unSentDocs)
    {
        $gErr = Globals::$g->gErr;

        // set _r so the editor knows which we are working on
        Request::$r->_r = $key;

        $docValues = $this->getDocumentType($key);

        if ( is_array($docValues) ) {
            $docType = $docValues['DOCTYPE'];
            $entityid = $docValues['ENTITYID'];
            $docclass = $docValues['DOCCLASS'];
        }

        /** @noinspection PhpUndefinedVariableInspection */
        $currentTemplate = $this->getTemplateType($key, $docType, $this->xslformat, $entityid, $docclass);

        if ( $currentTemplate['type'] == 'DOC' || $currentTemplate['type'] == 'DOX' ) {
            //make $savetodellog to true when it is both print/email with custom document
            //check whether xml has been created already for the same record in print option
            $dataXML = $this->custentityCache[$key]['xml'] ?? $this->getXMLForPrinting($key, true);

            if ( !$dataXML ) {
                // Track the documents that are not sent so we can report (or email) the sender
                $this->addUnsentDoc($unSentDocs, $key);
                return false;
            }

            list($langCode, $countryCode) = explode('-', $currentTemplate['LOCALE']);
            $langCode = ( $langCode != '' ? $langCode : 'en' );
            $countryCode = ( $countryCode != '' ? $countryCode : 'US' );

            $pdfParams = array(
                'LANGCODE' => $langCode,
                'COUNTRYCODE' => $countryCode,
                'WHENMODIFIED' => $currentTemplate['WHENMODIFIED'],
                'ENCRYPTPDF' => $currentTemplate['ENCRYPTPDF'],
            );

            // generate PDF
            $pdfdata = genPDFFromWORD($dataXML, $currentTemplate['template'], false, $pdfParams);
            $blobdata = $pdfdata;

        } else {
            //check whether xml has been created already for the same record in print option
            if (isset($this->custentityCache[$key]['fo'])) {
                $fo = $this->custentityCache[$key]['fo'];
            } else {
                $includeLayoutEditFile = strtolower($this->entity) . '_layout_edit.php';
                if ( stream_resolve_include_path($includeLayoutEditFile) ) {
                    include $includeLayoutEditFile;  // sets $top
                } else {
                    $msg = __METHOD__ . ':' . __FILE__ . ':' . __LINE__ . "; Cannot resolve include file '$includeLayoutEditFile' based on entity '{$this->entity}' (unable to set global var '\$top').\n";
                    logToFileWarning($msg);
                }
                // email is making the pdf and sending it via email, not out the browser.
                include_once 'backend_pdf.inc';

                $xsl = $this->getXSLTemplate($key, $docType, $this->xslformat);
                $xml = $this->getXMLForPrinting($key, false);

                $ok = XSLTInProcess($xsl, $xml, $fo);
                if (!$ok) {
                    $gErr->addIAError('INV-0122', __FILE__ . ":" . __LINE__,
                        "XSL Translation failed",
                        []
                    ); // Track the documents that are not sent so we can report (or email) the sender
                    $this->addUnsentDoc($unSentDocs, $key);
                    return false;
                }
            }
            // need to get the pdf back and attach it to the email somehow....
            $pdfdata = genPDF($fo, false);
            $blobdata = $fo;
        }

        return true;
    }

    /**
     * @param string|int    $key
     * @param string        $entityname
     *
     * @return string
     */
    protected function getEmailSubject($key, $entityname)
    {

        if ( $this->emailSubject[$key] ) {
            $subject = $this->emailSubject[$key];
        }
        else {
            $subject = $this->generateEmailSubject($key, $entityname);
        }

        return $subject;
    }

    /**
     * @return array
     */
    protected function getDateFieldsForEmailTemplate()
    {
        return [];
    }

    /**
     * @return array
     */
    protected function getDateTimeFieldsForEmailTemplate()
    {
        return [];
    }

    /**
     * @param array $row
     */
    protected function reformatDateFields(&$row)
    {
        // Converting default date format [mm/dd/yyyy] to user date format if prefered in email template.
        if ($this->_userPrefDateformat == 'T') {
            $dateFields = $this->getDateFieldsForEmailTemplate();
            foreach (($dateFields ?? []) as $dtFld) {
                $row[$dtFld] = FormatDateForDisplay($row[$dtFld]);
            }

            // Datetime feilds
            $dateTimeFields = $this->getDateTimeFieldsForEmailTemplate();
            foreach (($dateTimeFields ?? []) as $dttFld) {
                $row[$dttFld] = FormatTimestampForDisplay(GMTToUserTZ($row[$dttFld]));
            }
        }
    }

    /**
     * @param bool $canInsertIntoDeliveryLog
     */
    public function canInsertIntoDeliveryLog(bool $canInsertIntoDeliveryLog): void
    {
        $this->canInsertIntoDeliveryLog = $canInsertIntoDeliveryLog;
    }

    /**
     * @return string
     */
    public function getDeliveryLogObject(): string
    {
        return $this->deliveryLogObject;
    }

    /**
     * @param string $deliveryLogObject
     */
    public function setDeliveryLogObject(string $deliveryLogObject): void
    {
        $this->deliveryLogObject = $deliveryLogObject;
    }

    /**
     * @return string
     */
    public function getDeliveryLogDescription(): string
    {
        return $this->deliveryLogDescription;
    }

    /**
     * @param string $deliveryLogDescription
     */
    public function setDeliveryLogDescription(string $deliveryLogDescription): void
    {
        $this->deliveryLogDescription = $deliveryLogDescription;
    }

    /**
     * @return bool
     */
    public function isSmartEventsAttachEmail(): bool
    {
        return $this->smartEventsAttachEmail;
    }

    /**
     * @param bool $smartEventsAttachEmail
     */
    public function setSmartEventsAttachEmail(bool $smartEventsAttachEmail): void
    {
        $this->smartEventsAttachEmail = $smartEventsAttachEmail;
    }

    /**
     * @return bool
     */
    public function isPrintedFlagValidateWithConfig(): bool
    {
        return $this->printedFlagValidateWithConfig;
    }

    /**
     * @param bool $flag
     *
     * @return void
     */
    public function setPrintedFlagValidateWithConfig(bool $flag): void
    {
        $this->printedFlagValidateWithConfig = $flag;
    }

    /**
     * Add details into delivery log
     *
     * @param string $key
     * @param string $blobData
     * @param array  $attachments
     * @param string $deliveryOption
     *
     * @return array
     */
    protected function addIntoDeliveryLog(string $key, string $blobData,
                                          &$attachments, string $deliveryOption='P'): array
    {
        $deliverylog = [];
        // insert into delivery log, only if canInsertDeliveryLog is set as true
        if ($this->canInsertIntoDeliveryLog && !empty($key) && !empty($this->getDeliveryLogObject())) {
            $deliveryhistoryMgr = Globals::$g->gManagerFactory->getManager('deliveryhistory');
            // if printing happening from smart events attach email, set the delivery option to 'E'
            if ($this->isSmartEventsAttachEmail() === true) {
                $deliveryOption = 'E';
            }

            $deliverylog = [
                'OBJECT' => $this->getDeliveryLogObject(),
                'DELIVERYOPTIONS' => $deliveryOption,
                'ENTITY' => $this->custentityCache[$key]['CUSTENTITY'],
                'DOCUMENTDATE' => $this->custentityCache[$key]['DOCUMENTDATE'],
                'DESCRIPTION' => $this->getDeliveryLogDescription(),
                'XML' => $blobData
            ];

            if ( $this->mod === 'ar' ) {
                $deliverylog['PRRECORDKEY'] = $this->custentityCache[$key]['RECORDNO'];
            } elseif ( $this->mod === 'po' || $this->mod === 'so') {
                $deliverylog['DOCHDRKEY'] = $this->custentityCache[$key]['RECORDNO'];
            }

            $ok = true;
            // Just set SUPDOCKEY to delivery log record
            if (isset($this->emailDocIds[$key])) {
                $ok = $ok && $this->attachAndLogAttachments($key, $deliverylog, $attachments);
            }
            $ok = $ok && $deliveryhistoryMgr->add($deliverylog);
            if (!$ok) {
                $deliverylog = [];
            }
        }
        return $deliverylog;
    }
    
    /**
     * Returns maximum number of custom documents system can handle inside sinlge PDF
     *
     * @return int
     */
    protected function getMaxCustomDocsInPDF(): int
    {
        if (FeatureConfigManagerFactory::getInstance()->isFeatureEnabled('MAXIMIZE_CUSTOM_DOCUMENTS_IN_PDF')) {
            return static::$maxCustomDocsInPDF;
        }
        
        return static::$defaultMaxCustomDocsInPDF;
    }
}
