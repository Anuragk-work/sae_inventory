<?php

/*
 *	FILE: DocumentApprovalManager.cls 
 *	AUTHOR: Sudeendra Ramesh
 *	DESCRIPTION: 
 * 
 *	(C) 2005, Intacct Corporation, All Rights Reserved 
 * 
 *	This document contains trade secret data that belongs to Intacct 
 *	Corporation and is protected by the copyright laws.  Information 
 *	herein may not be used, copied or disclosed in whole or in part 
 *	without prior written consent from Intacct Corporation.
 */


import('ApprovalManager');
import('ManagerFactory');

/**
 * This class will handle all the document approval process, including submitting the document to approver, approving the document,
 * declining a document and notifying the approver.
 */
class DocumentApprovalManager extends ApprovalManager
{
    /**
     * @param array $params
     */
    public function __construct($params = array()) 
    {
        parent::__construct($params);
        // DE1520:  we must throw errors when employee manager if not resolved !
        $this->errorIfNoEmployeeManager = true;
    }

    /**
     * @param array $values
     *
     * @return bool|string[][]
     */
    public function ClearExistingApprovalRules($values)
    {
        $args = array (  $this->cny, $values['RECORDNO'], STATE_DECLINED );
        $ok = $this->DoQuery('QRY_APPROVAL_DELETE_BY_DOCHDRKEY', $args);

        return $ok;
    }

    /**
     * prepValues - create approval data structure
     *
     * @see ApprovalManager::PrepValues()
     *
     * @param array  $values
     * @param string $stage
     * @param int    $level
     * @param string $type
     * @param string $approverid
     * @param string $approverTitle
     * @param int    $approverNum
     * @param string $objectID
     * @param string $onDelegation
     * @param string $delegateId
     * @param string $approverGroupId
     *
     * @return array containing all necessary info for approval
     */
    protected function PrepValues($values, $stage, $level, $type, $approverid = '', $approverTitle = '', $approverNum = 1, $objectID = '', $onDelegation = 'false', $delegateId = '', $approverGroupId = '')
    {
        $approvalValues = parent::PrepValues($values, $stage, $level, $type, $approverid, $approverTitle, $approverNum, $objectID, $onDelegation, $delegateId);
        $approvalValues['DOCHDRKEY'] = $values['RECORDNO'];
            
        return $approvalValues;
    }

    /**
     * Update the current approval rule with the approve/decline status
     *
     * @param array $docvalues
     *
     * @return bool
     */
    protected function UpdateCurrentApprovalRule(&$docvalues) 
    {
            
        $qry = " select record#, dochdrkey, approval_stage, approval_type, approval_level, approverkey, state from approvalhistory where cny# = :1 and dochdrkey = :2 and state = :3 ";
        $res = QueryResult(array($qry, $this->cny, $docvalues['RECORDNO'], STATE_SUBMIT));

        $docvalues['CURRENTRULE'] = $res[0];

        $update_history = false;

        // if there are no approval steps remaining the document is already approved or declines so skip update
        if ( count($res) > 0 ) {
            if ($this->IsAdminApprover($this->userid)) {
                $update_history = true;
            } else if ($res[0]['APPROVAL_TYPE'] == APPTYPE_APPROVAL_LEVEL || $res[0]['APPROVAL_TYPE'] == APPTYPE_PROGRESS_APPROVAL_LEVEL) {
                // check to make sure that the user has permission and has not already approved the document
                if ($this->HasApprovalLevelPerm($res[0]['APPROVAL_LEVEL']) && !$this->HasApprovedStage($docvalues)) {
                    $update_history = true;
                }
            } else {
                if ($res[0]['APPROVERKEY'] == $this->userid) {
                    $update_history = true;
                }
            }
        }

        if ($update_history) {
            $updateRuleStmt = " UPDATE approvalhistory SET approvedbykey = :1, eventdate = :2, comments = :3, state = :4 WHERE record# = :5  AND cny# = :6 ";
            $ok = ExecStmt(
                array($updateRuleStmt,
                $this->userid,
                GetCurrentDate(),
                $docvalues['REVIEWCOMMENTS'],
                $docvalues['REVIEWACTION'],
                $res[0]['RECORD#'],
                $this->cny
                        )
            );
        } else {
            // DE1120-1123: We should return false when we fail to approve /decline the document due to permissions error otherwise
            // API approve/decline will return success whereas it really failed
            $ok = false;
            $this->update_state     = false;
        }

        return $ok;
    }

    /**
     * Check that the same person does not approve the same stage twice.
     *
     * @param array $docvalues
     *
     * @return bool
     */
    protected function HasApprovedStage($docvalues)
    {

        $qry = "select count(*) as cou from approvalhistory appHistory where appHistory.cny# = :1 and appHistory.dochdrkey = :2  and appHistory.approvedbykey = :4 and ( (appHistory.approval_type = '" . $this->GetValueApprovalTypeName() . "' and appHistory.state = :3 )
                or (appHistory.approval_type = '".APPTYPE_PROGRESS_APPROVAL_LEVEL."' and appHistory.approval_stage in ( select unique(apphis.approval_stage) from approvalhistory apphis where apphis.cny# = appHistory.cny# and apphis.dochdrkey = appHistory.dochdrkey and apphis.state = :5 )
                and appHistory.approval_level in (select min(apph.approval_level) from approvalhistory apph where apph.cny# = appHistory.cny# and apph.dochdrkey = appHistory.dochdrkey and apph.state = :5
                and apph.approval_stage = appHistory.approval_stage)) and  appHistory.state = :3 )";
        $result = QueryResult(array($qry, $this->cny, $docvalues['RECORDNO'], STATE_APPROVED, $this->userid, STATE_SUBMIT));
        if (isset($result) && $result[0]['COU'] > 0) {
            return true;
        }
        return false;
    }

    /**
     * Get the next approval rule in the approval chain.
     *
     * @param array $docvalues
     *
     * @return bool|array
     */
    protected function GetNextApprovalRule($docvalues) 
    {

        $nextRuleStmt = " select record#, approval_type, approverkey, approval_level, approval_stage, state, approver_number, delegatekey, ondelegation 
                          from approvalhistory
						  where cny# = :1
							and dochdrkey = :2
							and state = :3
							and record# = 
                            (select min(record#) from approvalhistory where cny# = :1 and dochdrkey = :2 and state = :3) ";

        $res = QueryResult(array($nextRuleStmt, $this->cny, $docvalues['RECORDNO'], STATE_PENDING));

        if (isset($res)) {
            return $res[0];
        } else {
            return false;
        }
    }

    /**
     * Check if the document approval chain has next approval rule. Is this the last rule ?
     *
     * @param array $docvalues
     *
     * @return bool
     */
    protected function HasNextApprovalRule($docvalues) 
    {

        $nextRuleStmt = " select record#, approval_type, approverkey, approval_level, approval_stage, state, delegatekey, ondelegation from approvalhistory
							where cny# = :1
							and dochdrkey = :2
							and state = :3 ";

        $res = QueryResult(array($nextRuleStmt, $this->cny, $docvalues['RECORDNO'], STATE_SUBMIT));

        if (isset($res)) {
            return $res[0];
        } else {
            return false;
        }
    }

    /**
     * mark all the approval rules for the document as declined.
     *
     * @param array $docvalues
     *
     * @return bool
     */
    protected function DisableApprovalRules(&$docvalues) 
    {
        $ok = true;

        $args = array ($this->cny, $docvalues['RECORDNO'], STATE_PENDING);
        $ok = $ok && $this->DoQuery('QRY_APPROVAL_DELETE_STATE_BY_DOCHDRKEY', $args);
         
        $docvalues['APPROVAL_STATE'] = STATE_DECLINED;

        return $ok;
    }
    
    // TODO : Dead Code - Remove UserDocApprovalPermission AND HasDocApprovalPermission method as they are not used anywhere

    /**
     * Get the subscriptions manager. Subclasses to implement this API.
     *
     * @return DocumentSetupManager|null
     */
    public function get_subscriptionwiz_manager()
    {
        return null;
    }

    /**
     * Subclasses to implement this API.
     *
     * @return ApprovalRuleManager|DocumentSetupManager|null
     */
    protected function getApprovalRuleManager() {
        return null;
    }

    /**
     * Subclasses to implement this API.
     *
     * @return POApprovalPolicyManager|POSetupManager|null
     */
    public function getApprovalPolicyManager() {
        return null;
    }

    /**
     * Check if the user has approval level permission for the particular level.
     *
     * @param string $level
     *
     * @return bool
     */
    protected function HasApprovalLevelPerm($level)
    {
        return false;
    }

    /**
     * @param array $values
     *
     * @return array list of approval steps or empty if none defined
     */
    protected function getApprovalPreferences($values)
    {
        // child classes should implement this method if using the new approval policy based setup
        return array();
    }

    /**
     * @param array $values
     *
     * @return array
     */
    protected function getDollarLevelApprovalPrefs($values)
    {
        // can return either old POSetupManager or ne approvalRule manager depending on feature flag
        $subswizMgr = $this->getApprovalRuleManager();
        if (isset($values['VALUEAPPROVAL_AMOUNT'])) {
            return $subswizMgr->getDollarLevelApprovalPrefs($values['VALUEAPPROVAL_AMOUNT']);
        }
        return $subswizMgr->getDollarLevelApprovalPrefs($values['APPROVALAMOUNT']);
    }

    /**
     * @param array $values
     *
     * @return array value approval setup data
     */
    protected function getProgressDollarLevelApprovalPrefs($values)
    {
        // can return either old POSetupManager or ne approvalRule manager depending on feature flag
        $subswizMgr = $this->getApprovalRuleManager();
        if (isset($values['VALUEAPPROVAL_AMOUNT'])) {
            return $subswizMgr->getProgressDollarLevelApprovalPrefs($values['VALUEAPPROVAL_AMOUNT']);
        }
        return $subswizMgr->getProgressDollarLevelApprovalPrefs($values['APPROVALAMOUNT']);

    }

    /**
     * @param array $values
     * @param string $dimtype
     * @param string $dimid
     * @param int $rulesetID
     *
     * @return array|null
     */
    protected function getApprovalRulePrefs($values, $dimtype, $dimid, $rulesetID)
    {
        // since poapprovalrule prefs only comes from poapprovalrule manager for now we force it to use that manager for all documents
        // TODO later on we can use the getApprovalRuleManager code implemented in subclasses
        $approvalRuleMgr = Globals::$g->gManagerFactory->getManager('poapprovalrule');

        if (isset($values['VALUEAPPROVAL_AMOUNT'])) {
            return $approvalRuleMgr->getApprovalRulewithDetails($values['VALUEAPPROVAL_AMOUNT'], $dimtype, $dimid, $rulesetID);
        }
        else {
            return $approvalRuleMgr->getApprovalRulewithDetails($values['APPROVALAMOUNT'], $dimtype, $dimid, $rulesetID);
        }
        
    }

    /**
     * @param string $_r
     * @param string $total
     *
     * @return bool
     */
    protected function canSendValueEmail($_r, $total) 
    {
        $usrprofile = UserCacheHandler::getInstance(null, $_r);

        $sendValueEmail = false;

        if ($usrprofile->getProperty('USERPREF', 'PURENABLEEMAIL') === 'Y' && $total >= intval($usrprofile->getProperty('USERPREF', 'PURAMOUNTFOREMAIL')) ) {
            $sendValueEmail = true;
        }

        return $sendValueEmail;
    }

    /**
     * @param int $approverUserRecNum
     *
     * @return bool
     */
    protected function canSendEmail($approverUserRecNum)
    {
        $sendEmail = true;
        $usrprofile = UserCacheHandler::getInstance(null, $approverUserRecNum);

        if ( $usrprofile->getProperty('USERPREF', 'PURENABLEEMAIL') != 'Y' ) {
            $sendEmail = false;
        }
        return $sendEmail;
    }

    /**
     * @param string $userid
     *
     * @return bool
     */
    protected function IsAdminApprover($userid)
    {
        /** @var POSetupManager $subswizMgr */
        $subswizMgr = $this->get_subscriptionwiz_manager();
        return $subswizMgr->IsAdminApprover($userid);
    }

    /**
     * @return bool
     */
    protected function IsEmailNotificationsEnabled()
    {
        /** @var POSetupManager $subswizMgr */
        $subswizMgr = $this->get_subscriptionwiz_manager();
        return $subswizMgr->IsEmailNotificationsEnabled();
    }

    /**
     * @return string
     */
    protected function GetValueApprovalTypeName()
    {
        return APPTYPE_APPROVAL_LEVEL;
    }

    /**
     * @param string $level
     *
     * @return string[][]|false
     */
    protected function getValueLevelUsers($level)
    {
        global $gManagerFactory;
        $approverPickMgr = $gManagerFactory->getManager('approverpick');
        return $approverPickMgr->getAuthorizedValueLevelUsers('Level'.$level);
    }

    /**
     * @return string
     */
    protected function BuildLandPageOp()
    {
        $approvelistop = GetOperationId('po/activities/approvepurchases');
        return "fo=po&.navop=".$approvelistop;
    }

    /**
     * @param array $values
     * @param string $approveruserid
     * @param int $approverUserRecNum
     * @param array $contactObj
     * @param string $url
     * @param array $rule
     *
     * @return string
     */
    protected function BuildApprovalMessage($values, $approveruserid, $approverUserRecNum, $contactObj, $url, $rule)
    {
        $docno = $values['DOCNO'];
        $date = IADateTime::getCurrentDateWithMonthAsWord();
        
        // The following code is to get the user information irrespective of MEGA context.
        $qry = " select loginid from userinfomst where cny# = :1 and record# = :2 ";
        $createdUser = QueryResult(array($qry, $this->cny, $values['CREATEDUSER']));

        // This amount will be set twice, once in PostProcessDocument API call on submission and second on all approval action.
        $total = $values['APPROVALAMOUNT'];
        $emailToken = $this->getI18NEmailTokenObject(NOTIFY_APPROVER);
        //constructing body text
        $total = glFormatCurrency($total);
        if ($this->ismcpEnabled) {
            //constructing body msgMCPEnabled text, if mcp enabled
            $msg = $emailToken->applyPlaceholders(
                'body.msgMCPEnabled',
                [
                    'CONTACT_FIRSTNAME' => $contactObj['FIRSTNAME'],
                    'USER_LOGINID'      => $createdUser[0]['LOGINID'],
                    'DOCNO'             => $docno,
                    'DATE_SUBMITTED'    => $date,
                    'VENDOR_ID'         => $values['CUSTVENDID'],
                    'VENDOR_NAME'       => $values['CUSTVENDNAME'],
                    'TRX_CURR_VALUE'    => $values['CURRENCY'],
                    'TRX_AMOUNT_VALUE'  => $values['TRX_TOTAL'],
                    'BASE_CURR_VALUE'   => $values['BASECURR'],
                    'TOTAL_VALUE'       => $total,
                    'MESSAGE'           => $values['MESSAGE'],
                    'URL'               => $url,
                    'COMPANY_TITLE'     => GetMyCompanyTitle(),
                    'COMPANY_NAME'      => GetMyCompanyName()
                ]
            );
        }else{
            $total = $total." ".$values['CURRENCY'];
            //constructing body msgNoMCPEnabled text, if no mcp enabled
            $msg = $emailToken->applyPlaceholders(
                'body.msgNoMCPEnabled',
                [
                    'CONTACT_FIRSTNAME' => $contactObj['FIRSTNAME'],
                    'USER_LOGINID'      => $createdUser[0]['LOGINID'],
                    'DOCNO'             => $docno,
                    'DATE_SUBMITTED'    => $date,
                    'VENDOR_ID'         => $values['CUSTVENDID'],
                    'VENDOR_NAME'       => $values['CUSTVENDNAME'],
                    'TOTAL_VALUE'       => $total,
                    'MESSAGE'           => $values['MESSAGE'],
                    'URL'               => $url,
                    'COMPANY_TITLE'     => GetMyCompanyTitle(),
                    'COMPANY_NAME'      => GetMyCompanyName()
                ]
            );
        }

        return $msg;
    }

    /**
     * @param array $values
     * @param array $contactObj
     *
     * @return string
     */
    protected function BuildApprovalSubject($values, $contactObj)
    {
        $emailToken = $this->getI18NEmailTokenObject(NOTIFY_APPROVER);
        return $this->getBuildApprovalSubjectText($emailToken);
    }

    /**
     * @param array $values
     * @param string $approveruserid
     * @param array $contactObj
     * @param string $action
     *
     * @return string
     */
    protected function BuildActionMessage($values, $approveruserid, $contactObj, $action)
    {
        $docparID = $values['DOCPARID'];
        $docno = $values['DOCNO'];
        $amount = glFormatCurrency($values['APPROVALAMOUNT']);

        $emailToken = $this->getI18NEmailTokenObject(APPROVER_ACTION);
        //constructing body text
        if ($action === 'declined') {
            //constructing body msgActionDecline text
            $msg = $emailToken->applyPlaceholders(
                'body.msgActionDecline',
                [
                    'FIRSTNAME' =>  $contactObj['FIRSTNAME'],
                    'DOCPAR_ID' =>  $docparID,
                    'DOCNO'     =>  $docno,
                    'AMOUNT'    =>  $amount,
                    'BASECURR'  =>  $values['BASECURR'],
                    'REVIEWCOMMENTS'=>  $values["REVIEWCOMMENTS"],
                    'COMPANYTITLE'  =>  GetMyCompanyTitle(),
                    'COMPANYNAME'   =>  GetMyCompanyName()
                ]
            );
        }else{
            //constructing body msgActionApproved text
            $msg = $emailToken->applyPlaceholders(
                'body.msgActionApproved',
                [
                    'FIRSTNAME' =>  $contactObj['FIRSTNAME'],
                    'DOCPAR_ID' =>  $docparID,
                    'DOCNO'     =>  $docno,
                    'AMOUNT'    =>  $amount,
                    'BASECURR'  =>  $values['BASECURR'],
                    'REVIEWCOMMENTS'=>  $values["REVIEWCOMMENTS"],
                    'COMPANYTITLE'  =>  GetMyCompanyTitle(),
                    'COMPANYNAME'   =>  GetMyCompanyName()
                ]
            );
        }
        return $msg;
    }

    /**
     * @param array $values
     * @param array $contactObj
     * @param string $action
     *
     * @return string
     */
    protected function BuildActionSubject($values, $contactObj, $action)
    {
        $docparID = $values['DOCPARID'];
        $docno = $values['DOCNO'];
        $emailToken = $this->getI18NEmailTokenObject(APPROVER_ACTION);
        //constructing subject text and return
        if ($action === 'declined') {
            return $emailToken->applyPlaceholders(
                'subject.textDeclined',
                [
                    'DOCPAR_ID' => $docparID,
                    'DOCNO'     => $docno
                ]
            );
        }else{
            return $emailToken->applyPlaceholders(
                'subject.textApproved',
                [
                    'DOCPAR_ID' => $docparID,
                    'DOCNO'     => $docno
                ]
            );
        }
    }
    
    /**
     * API to send the email notification to the approver on submission of the document.
     *
     * @see ApprovalManager::SendApprovalNotification
     *
     * Overridden so we can handle the userpref to disable per-user notifications
     *
     * @param array   $values             document values
     * @param array   $contactObj         the contact information for the approving user
     * @param string  $approveruserid     the approving user's login id
     * @param int $approverUserRecNum the approving user's record#
     * @param array   $rule               the workflow rule being executed
     *
     * @return bool pretty much always true
     */
    public function SendApprovalNotification($values, $contactObj, $approveruserid, $approverUserRecNum, $rule)
    {

        if ( !$this->canSendEmail($approverUserRecNum) ) {
            return true;
        }

        if ( !$this->isDocTypeAllowedForUser($values, $approverUserRecNum) ) {
            return true;
        }

        return parent::SendApprovalNotification($values, $contactObj, $approveruserid, $approverUserRecNum, $rule);
    }

    /**
     * @param string $approveruserid
     *
     * @return string
     */
    protected function BuildUrl(string $approveruserid) : string
    {
        $applicationServerUrl = '';
        if (FeatureConfigManagerFactory::getInstance()->isFeatureEnabled(
            'ENABLE_APPROVAL_EMAIL_URL_USING_APPLICATION_SERVER'
        )) {
            $applicationServerUrl = GetValueForIACFGProperty('IA_APPLICATION_SERVER');
        }
        $url = Autoslide::buildAutoslideLoginUrl(
            $approveruserid,
            $this->BuildLandPageOp(),
            $applicationServerUrl
        );
        $displayTxt = I18N::getSingleToken('IA.DISPLAY');
        return "<a href='" . $url . "'>$displayTxt</a>";
    }

    /**
     * @return string
     */
    protected function BuildDelegateSubject()
    {
        $emailToken = $this->getI18NEmailTokenObject(DELEGATE_NOTIFICATION);
        // Build and return the subject
        return $emailToken->applyPlaceholders(
            'subject.text',
            [
            ]
        );
    }

    /**
     * @param array $values
     * @param array $contactObj
     * @param array $delegateContact
     * @param string $approverUserId
     *
     * @return string
     */
    protected function BuildDelegateMessage($values, $contactObj, $delegateContact, $approverUserId)
    {
        $applicationServerUrl = '';
        if (FeatureConfigManagerFactory::getInstance()->isFeatureEnabled(
            'ENABLE_APPROVAL_EMAIL_URL_USING_APPLICATION_SERVER'
        )) {
            $applicationServerUrl = GetValueForIACFGProperty('IA_APPLICATION_SERVER');
        }
        //Build url for user pref
        $url = Autoslide::buildAutoslideLoginUrl(
            $approverUserId,
            'fo=co&.navop='.GetOperationId('co/setup/userpref'),
            $applicationServerUrl
        );
        $displaytext = I18N::getSingleToken('IA.TURN_OFF');
        $userPrefUrl = "<a href='" . $url . "'>$displaytext</a>";

        $docno = $values['DOCNO'];
        $date = IADateTime::getCurrentDateWithMonthAsWord();

        // The following code is to get the user information irrespective of MEGA context.
        $qry = " select loginid from userinfomst where cny# = :1 and record# = :2 ";
        $createdUser = QueryResult(array($qry, $this->cny, $values['CREATEDUSER']));

        $total = $values['APPROVALAMOUNT'];

        $emailToken = $this->getI18NEmailTokenObject(DELEGATE_NOTIFICATION);
        //constructing body text
        if ($this->ismcpEnabled) {
            //constructing body msgMCPEnabled text, if mcp enabled
            $msg = $emailToken->applyPlaceholders(
                'body.msgMCPEnabled',
                [
                    'CONTACT_FIRSTNAME' => $contactObj['FIRSTNAME'],
                    'DELEGATE_FIRSTNAME'=> $delegateContact['FIRSTNAME'],
                    'USER_LOGINID'      => $createdUser[0]['LOGINID'],
                    'DOCNO'             => $docno,
                    'DATE_SUBMITTED'    => $date,
                    'VENDOR_ID'         => $values['CUSTVENDID'],
                    'VENDOR_NAME'       => $values['CUSTVENDNAME'],
                    'TRX_CURR_VALUE'    => $values['CURRENCY'],
                    'TRX_AMOUNT_VALUE'  => $values['TRX_TOTAL'],
                    'BASE_CURR_VALUE'   => $values['BASECURR'],
                    'TOTAL_VALUE'       => $total,
                    'CURRENCY'          => $values['CURRENCY'],
                    'USERPREFURL'       => $userPrefUrl,
                    'COMPANY_TITLE'     => GetMyCompanyTitle(),
                    'COMPANY_NAME'      => GetMyCompanyName()
                ]
            );
        }else{
            //constructing body msgNoMCPEnabled text, if no mcp enabled
            $msg = $emailToken->applyPlaceholders(
                'body.msgNoMCPEnabled',
                [
                    'CONTACT_FIRSTNAME' => $contactObj['FIRSTNAME'],
                    'DELEGATE_FIRSTNAME'=> $delegateContact['FIRSTNAME'],
                    'USER_LOGINID'      => $createdUser[0]['LOGINID'],
                    'DOCNO'             => $docno,
                    'DATE_SUBMITTED'    => $date,
                    'VENDOR_ID'         => $values['CUSTVENDID'],
                    'VENDOR_NAME'       => $values['CUSTVENDNAME'],
                    'TOTAL_VALUE'       => $total,
                    'CURRENCY'          => $values['CURRENCY'],
                    'USERPREFURL'       => $userPrefUrl,
                    'COMPANY_TITLE'     => GetMyCompanyTitle(),
                    'COMPANY_NAME'      => GetMyCompanyName()
                ]
            );
        }
        return $msg;
    }

    /**
     * @param I18NEmailToken $emailToken
     * @return string
     */
    private function getBuildApprovalSubjectText(I18NEmailToken $emailToken)
    {
        // Build and return the subject
        return $emailToken->applyPlaceholders(
            'subject.text',
            [
            ]
        );
    }

    /**
     * @return string
     */
    protected function BuildDelegateApprovalSubject()
    {
        $emailToken = $this->getI18NEmailTokenObject(NOTIFY_DELEGATE_APPROVER);
        return $this->getBuildApprovalSubjectText($emailToken);
    }

    /**
     * @param array $values
     * @param array $contactObj
     * @param array $delegateContct
     * @param string $url
     *
     * @return string
     */
    protected function BuildDelegateApprovalMessage($values, $contactObj, $delegateContct, $url)
    {
        $docno = $values['DOCNO'];
        $date = IADateTime::getCurrentDateWithMonthAsWord();

        // The following code is to get the user information irrespective of MEGA context.
        $qry = " select loginid from userinfomst where cny# = :1 and record# = :2 ";
        $createdUser = QueryResult(array($qry, $this->cny, $values['CREATEDUSER']));

        $total = $values['APPROVALAMOUNT'];

        $emailToken = $this->getI18NEmailTokenObject(NOTIFY_DELEGATE_APPROVER);
        //constructing body text
        if ($this->ismcpEnabled) {
            //constructing body msgMCPEnabled text, if mcp enabled
            $msg = $emailToken->applyPlaceholders(
                'body.msgMCPEnabled',
                [
                    'CONTACT_FIRSTNAME' => $contactObj['FIRSTNAME'],
                    'DELEGATE_FIRSTNAME'=> $delegateContct['FIRSTNAME'],
                    'USER_LOGINID'      => $createdUser[0]['LOGINID'],
                    'DOCNO'             => $docno,
                    'DATE_SUBMITTED'    => $date,
                    'VENDOR_ID'         => $values['CUSTVENDID'],
                    'VENDOR_NAME'       => $values['CUSTVENDNAME'],
                    'TRX_CURR_VALUE'    => $values['CURRENCY'],
                    'TRX_AMOUNT_VALUE'  => $values['TRX_TOTAL'],
                    'BASE_CURR_VALUE'   => $values['BASECURR'],
                    'TOTAL_VALUE'       => $total,
                    'CURRENCY'          => $values['CURRENCY'],
                    'MESSAGE'           => $values['MESSAGE'],
                    'URL'               => $url,
                    'COMPANY_TITLE'     => GetMyCompanyTitle(),
                    'COMPANY_NAME'      => GetMyCompanyName()
                ]
            );
        }else{
            //constructing body msgNoMCPEnabled text, if mcp enabled
            $msg = $emailToken->applyPlaceholders(
                'body.msgNoMCPEnabled',
                [
                    'CONTACT_FIRSTNAME' => $contactObj['FIRSTNAME'],
                    'DELEGATE_FIRSTNAME'=> $delegateContct['FIRSTNAME'],
                    'USER_LOGINID'      => $createdUser[0]['LOGINID'],
                    'DOCNO'             => $docno,
                    'DATE_SUBMITTED'    => $date,
                    'VENDOR_ID'         => $values['CUSTVENDID'],
                    'VENDOR_NAME'       => $values['CUSTVENDNAME'],
                    'TOTAL_VALUE'       => $total,
                    'CURRENCY'          => $values['CURRENCY'],
                    'MESSAGE'           => $values['MESSAGE'],
                    'URL'               => $url,
                    'COMPANY_TITLE'     => GetMyCompanyTitle(),
                    'COMPANY_NAME'      => GetMyCompanyName()
                ]
            );
        }
        return $msg;
    }

    /**
     * Check if the user is allowed for this Document Type.
     * isDocTypeAllowedForUser function checks whether a user is restricted for Document Type.
     * If user is restricted the we will not send email notification to that particular user.
     *
     * @param array $values
     * @param int $approverUserRecNum
     *
     * @return bool
     */
    function isDocTypeAllowedForUser($values, $approverUserRecNum)
    {
        $ok = true;
        $transactionType = $values['_DOCPAR']['DOCID'];
        $userPerm  = $values['_DOCPAR']['USERPERM'];
        if(isset($transactionType) && $userPerm == 'true' ){
            $fs = new FSEntityManager();
            if (!$fs->IsPathAllowedForUser($transactionType, $approverUserRecNum, 'po', 'Purchase Document')) {
                $ok = false;
            }
        }

        return $ok;
    }

    /**
     * @param string $emailType
     * @return I18NEmailToken
     */
    protected function getI18NEmailTokenObject(string $emailType) : I18NEmailToken
    {
        $emailTokenId = "";
        switch($emailType){
            case NOTIFY_APPROVER:
                $emailTokenId = "IA.EMAIL.PURCHASING.NOTIFY_APPROVER";
                break;
            case APPROVER_ACTION:
                $emailTokenId = "IA.EMAIL.PURCHASING.APPROVER_ACTION";
                break;
            case DELEGATE_NOTIFICATION:
                $emailTokenId = "IA.EMAIL.PURCHASING.DELEGATE_NOTIFICATION";
                break;
            case NOTIFY_DELEGATE_APPROVER:
                $emailTokenId = "IA.EMAIL.PURCHASING.NOTIFY_DELEGATE_APPROVER";
                break;
        }
        return I18NEmailToken::buildFromResource($emailTokenId);
    }
}

