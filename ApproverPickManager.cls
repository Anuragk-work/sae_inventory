<?php
/**
*   FILE: ApproverPickManager.cls
*   AUTHOR: srao
*   DESCRIPTION:
*
*   (C) 2000, Intacct Corporation, All Rights Reserved
*
*   This document contains trade secret data that belongs to Intacct
*   Corporation and is protected by the copyright laws.  Information
*   herein may not be used, copied or disclosed in whole or in part
*   without prior written consent from Intacct Corporation.
*/

//import('EntityManager');
import('ApprovalManager');

require_once "cpa_util.inc";

class ApproverPickManager extends EntityManager
{

    /**
     * @var bool $isadminapprover
     */
    var $isadminapprover = false;
    /**
     * @var bool $isMultiEntityAware
     */
    var $isMultiEntityAware = false;
    /**
     * @var array $IgnoreListForOPID
     */
    private $IgnoreListForOPID = array();
    /**
     * @var array $AuthorizedUsersForOPID
     */
    private $AuthorizedUsersForOPID = array();


    /**
     * @param array $params
     */
    function __construct($params = array())
    {
        if (isset($params['isadmin'])) {
            $this->isadminapprover = true;
        }
        if ( isset($params['multiEntityAware']) ) {
            $this->isMultiEntityAware = true;
        }
        parent::__construct($params);
    }


    /**
     * @return mixed
     */
    private function myGetSystemApprovers()
    {
        // this is wrapper function to circumvent the PHP issue of not allowing the subclasses to overwrite static methods
        return call_user_func(array(get_class($this), 'GetSystemApprovers'));
    }

    /**
     * @return array
     */
    public static function GetSystemApprovers()
    {
        $approvers = array();
        $approvers[] = array ( 'PICKID' => APPTYPE_APPROVAL_LEVEL );
        $approvers[] = array ( 'PICKID' => APPTYPE_PROGRESS_APPROVAL_LEVEL );
        $approvers[] = array('PICKID' => APPTYPE_VALUE_EMPL_DEPT_RULE);
        $approvers[] = array('PICKID' => APPTYPE_VALUE_TXN_DEPT_RULE);
        $approvers[] = array ( 'PICKID' => APPTYPE_DEPT_LEVEL );
        $approvers[] = array ( 'PICKID' => APPTYPE_EMPLMNGR_LEVEL );
        $approvers[] = array ( 'PICKID' => APPTYPE_TRX_DEPT_LEVEL );

        // Transaction Location Approval will be enabled for cases other than where root is a working entity.
        // this is becase for a root as working entity, we will not be able to assign a manager to the root entity and so no transaction
        // will go through the approval process successfully.
        if (!GetRootContextLocation()) {
            $approvers[] = array ( 'PICKID' => APPTYPE_TRX_LOC_LEVEL );
        }

        // We will add project approval only is the Project Application is susbcribed
        global $kPAid;
        if( IsInstalled($kPAid) ) {
            $approvers[] = array ( 'PICKID' => APPTYPE_TRX_PROJMNGR_LEVEL );
        }

        return $approvers;
    }

    /**
     * @return string
     */
    protected function GetApproveOperationName()
    {
        return 'Approve Purchase Transaction';
    }

    /**
     * @return string
     */
    protected function GetApproveOperationModule()
    {
        return 'po';
    }

    /**
     * Get the operation name for the Value level approval
     *
     * @return string the operation name
     */
    protected function GetApproveValueLevelOperationName()
    {
        return 'Purchasing Approval Levels';
    }

    /**
     * @return string
     */
    protected function GetApproveOperationVerb()
    {
        return '%list%';
    }

    /**
     * Get list overridden to return the users that are authorized for approval.
     *
     * @param array $params
     * @param bool  $_crosscny
     * @param bool  $nocount
     *
     * @return array|array[]|mixed
     */
    function GetList($params = [], $_crosscny = false, $nocount = true)
    {
        AdvAuditTracking::setManagedTracking(false);
        $res = $this->getAuthorizedApprovalUsers();

        $approvers = array();

        $systemApprovers = $this->myGetSystemApprovers();
        if( is_array($systemApprovers) ) {
            $approvers = self::convertSystemApproversToExternalLabels($systemApprovers);
        }

        foreach ( $res as $value) {
            $pickid = $value['LOGINID'];
            if (isset($value['DESCRIPTION'])) {
                $pickid .= "--".$value['DESCRIPTION'];
            }
            $approvers[]= array ( 'PICKID' => $pickid );
        }

        if (count($approvers) > 0) {
            // We need to send this value to display the proper count on the picker/lister.
            $approvers[0]['QCNT'] = count($approvers);
        }

        return $approvers;
    }

    /**
     * @param array $params
     *
     * @return int
     */
    function GetCount($params)
    {
        return count($this->GetList());
    }

    /**
     * Get a list of users that have approve purchasing Transaction Permission.
     * (users must also have an email address and contact)
     * @param string $locationKey
     *
     * @return array
     */
    function getAuthorizedApprovalUsers($locationKey = null)
    {

        $opid = GetOperationId($this->GetApproveOperationKey());
        $extUsers = $this->_GetAuthorizedApprovalUsers($opid, $ignoreList);

        $meLocation = (isset($locationKey) && $locationKey != '') ? $locationKey : getMEContextLocation();
        if ( $meLocation && $this->isMultiEntityAware ) {
            $locationRestrictionClause = "(    ( userinfo.unrestricted = 'T' AND userinfo.locationkey is null )
                                            OR (     userinfo.unrestricted <> 'T'
                                                 and exists(select 1 from userloc
                                                            where cny#=userinfo.cny#
                                                             and userkey=userinfo.record#
                                                             and locationkey='$meLocation') ) )";
        } else {
            $locationRestrictionClause = "userinfo.unrestricted = 'T' AND userinfo.locationkey is null";
        }


        if (IsRolesEnabled()) {


            $qry1 = " SELECT userinfo.record#,
  					contact.email1        ,
					contact.printas		  , 
					contact.name    	  , 
  					userinfo.permissions  ,
  					userinfo.unrestricted ,
  					userinfo.loginid      ,
  					userinfo.type         ,
  					userinfo.admin        ,
 					userinfo.description  
				   FROM userinfomst userinfo,
					contact, rolepolicyassignment p, iapolicy iap, role_users uroles, roles roles
				   WHERE userinfo.status = 'T'
					AND userinfo.contactkey = contact.record#
					AND userinfo.cny#       = ?
					AND " . $locationRestrictionClause . "
					AND contact.cny#        = ?

					--
					and uroles.cny# = userinfo.cny#
					and uroles.userkey = userinfo.record#
					--
					and roles.cny# = uroles.cny#
					and roles.record# = uroles.rolekey
					and roles.applyto in ('B', 'L')
					--

					AND iap.module  = '" . $this->GetApproveOperationModule() . "'
					AND iap.name = '" . $this->GetApproveOperationName() . "'
					AND p.cny# = ?
					AND p.policykey = iap.record#
					AND p.rolekey = roles.record#
					AND p.policyval like '" . $this->GetApproveOperationVerb() . "' ";

             $qry2 = " SELECT userinfo.record#,
  					contact.email1        ,
					contact.printas		  , 
					contact.name    	  , 
  					userinfo.permissions  ,
  					userinfo.unrestricted ,
  					userinfo.loginid      ,
  					userinfo.type         ,
  					userinfo.admin        ,
 					userinfo.description
				   FROM userinfomst userinfo,
					contact, policyassignment p, iapolicy iap, externassoc ea
				   WHERE userinfo.status = 'T'
					AND userinfo.contactkey = contact.record#
					AND userinfo.cny#       = ?
					AND " . $locationRestrictionClause . "
					AND ea.externuserkey = userinfo.record#
					AND ea.cny# = userinfo.cny#
					AND ea.type = 'P'
					AND contact.cny# = userinfo.cny# 
					AND iap.module  = '" . $this->GetApproveOperationModule() . "'
					AND iap.name = '" . $this->GetApproveOperationName() . "'
					AND p.cny# = userinfo.cny# 
					AND p.policykey = iap.record#
					AND p.user_role_key = userinfo.record#
					AND p.policyval like '" . $this->GetApproveOperationVerb() . "' ";

            $query = array('QUERY' => " $qry1 UNION $qry2 ",
                           'ARGTYPES' => array('integer'));
        } else {
            $query = array('QUERY' => " SELECT userinfo.record#,
  					contact.email1        ,
					contact.printas		  , 
					contact.name		  , 
  					userinfo.permissions  ,
  					userinfo.unrestricted ,
  					userinfo.loginid      ,
  					userinfo.type         ,
  					userinfo.admin        ,
 					userinfo.description  
				   FROM userinfomst userinfo,
					contact, policyassignment p, iapolicy iap
				   WHERE userinfo.status = 'T'
					AND userinfo.contactkey = contact.record#
					AND userinfo.cny#       = ?
					AND " . $locationRestrictionClause . "
					AND contact.cny#        = ?
					AND iap.module  = '" . $this->GetApproveOperationModule() . "'
					AND iap.name = '" . $this->GetApproveOperationName() . "'
					AND p.cny# = ?
					AND p.policykey = iap.record#
					AND p.user_role_key = userinfo.record#
					AND p.policyval like '" . $this->GetApproveOperationVerb() . "' ",
                           'ARGTYPES' => array('integer', 'integer','integer'));
        }
        $query['QUERY'] = PrepINClauseStmt($query['QUERY'], $ignoreList, " and userinfo.loginid NOT ");
        $values = array();
        $allUsers = $this->_QM->DoCustomQuery($query, $values, true);
        $allUsers = array_merge($allUsers, $extUsers);

        return $allUsers;
    }


    /**
     * Get a list of users who have value approval permission for that particular level.
     * (users must also have an email address and contact)
     *
     * @param string $level
     *
     * @return bool|string[][]
     */
    function getAuthorizedValueLevelUsers($level)
    {
        //Fix for PDLC-0974-15 Send notifications to Approver if approver has same entity restrictions
        $meLocation = getMEContextLocation();
        //check if the approval is for the location/entity, if so get all the approvers including
        //approvers restricted to that location/entity.
        if ( $meLocation ) {
            $locationRestrictionClause = "(    ( userinfo.unrestricted = 'T' AND userinfo.locationkey is null )
                                            OR (     userinfo.unrestricted <> 'T'
                                                 and exists(select 1 from userloc
                                                            where cny#=userinfo.cny#
                                                             and userkey=userinfo.record#
                                                             and locationkey='$meLocation') ) )";
        } else {
            $locationRestrictionClause = "userinfo.unrestricted = 'T' AND userinfo.locationkey is null";
        }
        $extUsers = [];
        $ignoreList = [];
        if (IsRolesEnabled()) {
            $opid = GetOperationId($this->GetApproveOperationKey() . '/' . $level);
            $extUsers = $this->_GetAuthorizedApprovalUsers($opid, $ignoreList);


            $qry1 = " SELECT userinfo.record#,
  					contact.email1        ,
					contact.printas		  , 
  					userinfo.permissions  ,
  					userinfo.unrestricted ,
  					userinfo.loginid      ,
 					userinfo.description  ,
                    contact.firstname
				   FROM userinfomst userinfo,
					contact, rolepolicyassignment p, iapolicy iap, role_users uroles, roles roles
				   WHERE userinfo.status = 'T'
					AND userinfo.contactkey = contact.record#
					AND userinfo.cny#       = ?
					AND " . $locationRestrictionClause . "
					AND contact.cny#        = ?

					--
					and uroles.cny# = userinfo.cny#
					and uroles.userkey = userinfo.record#
					--
					and roles.cny# = uroles.cny#
					and roles.record# = uroles.rolekey
					and roles.applyto in ('B', 'L')
					--

					AND iap.module  = '" . $this->GetApproveOperationModule() . "'
					AND iap.name = '" . $this->GetApproveValueLevelOperationName() . "'
					AND p.cny# = ?
					AND p.policykey = iap.record#
					AND p.rolekey = roles.record#
					AND p.policyval like '%$level%' ";

            $qry2 = " SELECT userinfo.record#,
  					contact.email1        ,
					contact.printas		  , 
  					userinfo.permissions  ,
  					userinfo.unrestricted ,
  					userinfo.loginid      ,
 					userinfo.description  ,
                    contact.firstname
				   FROM userinfomst userinfo,
					contact, policyassignment p, iapolicy iap, externassoc ea
				   WHERE userinfo.status = 'T'
					AND userinfo.contactkey = contact.record#
					AND userinfo.cny#       = ?
					AND " . $locationRestrictionClause . "
					AND ea.externuserkey = userinfo.record#
					AND ea.cny# = userinfo.cny#
					AND ea.type = 'P'
					AND contact.cny# = userinfo.cny# 
					AND iap.module  = '" . $this->GetApproveOperationModule() . "'
					AND iap.name = '" . $this->GetApproveValueLevelOperationName() . "'
					AND p.cny# = userinfo.cny# 
					AND p.policykey = iap.record#
					AND p.user_role_key = userinfo.record#
					AND p.policyval like '%$level%' ";

            $query = array('QUERY' => " $qry1 UNION $qry2 ",
                           'ARGTYPES' => array('integer', 'integer','integer'));
        } else {
            $query = array('QUERY' => " SELECT userinfo.record#,
  					contact.email1        ,
					contact.printas		  , 
  					userinfo.permissions  ,
  					userinfo.unrestricted ,
  					userinfo.loginid      ,
 					userinfo.description  ,
                    contact.firstname
				   FROM userinfomst userinfo,
					contact, policyassignment p, iapolicy iap
				   WHERE userinfo.status = 'T'
					AND userinfo.contactkey = contact.record#
					AND userinfo.cny#       = ?
					AND " . $locationRestrictionClause . "
					AND contact.cny#        = ?
					AND iap.module  = '" . $this->GetApproveOperationModule() . "'
					AND iap.name = '" . $this->GetApproveValueLevelOperationName() . "'
					AND p.cny# = ?
					AND p.policykey = iap.record#
					AND p.user_role_key = userinfo.record#
					AND p.policyval like '%$level%' ",
                           'ARGTYPES' => array('integer', 'integer','integer'));
        }
        if (!empty($ignoreList)) {
            $query['QUERY'] = PrepINClauseStmt($query['QUERY'], $ignoreList, ' and userinfo.loginid NOT ');
        }
        $values = array();
        $allUsers = $this->_QM->DoCustomQuery($query, $values, true);
        $allUsers = array_merge($allUsers, $extUsers);

        return $allUsers;
    }


    /**
     * Get a list of users that have permision for a given operation (opid)
     * (users must also have an email address and contact)
     *
     * Modified by Tim Wasson to only return active, non-hidden users?
     *
     * @param int $opid
     * @param array $ignoreList
     *
     * @return array
     */
    function _GetAuthorizedApprovalUsers($opid,&$ignoreList)
    {

            // If Userkey's are already cached, do not do it again.
            // Otherwise proceed and do logic to obtain it.
        if(isset($this->AuthorizedUsersForOPID[$opid])) {
                // ticket 66933 need to set the ignorelist output variable from cache as well !
                $ignoreList = $this->IgnoreListForOPID[$opid] ?? [];

            // New variable to cache Userkey per OPID
                return $this->AuthorizedUsersForOPID[$opid];
        }

            $query = array('QUERY' => "SELECT 
                                    userinfo.record#, 
                                    contact.email1, 
                                    contact.name, 
                                    userinfo.permissions,
                                    userinfo.unrestricted,
                                    userinfo.loginid,
                                    userinfo.type,
                                    userinfo.admin,
                                    contact.printas
                            FROM userinfomst userinfo, contact
                            WHERE 
                                    userinfo.status = 'T' and
                                    userinfo.category = '" . UserInfoManager::CATEGORY_EXTERNAL . "' and
                                    userinfo.contactkey = contact.record# and 
                                    userinfo.cny# = ? and 
                                    contact.cny# = ?",
                           'ARGTYPES' => array('integer', 'integer'));

            $values = array();

            // All the users who has a contact key and status = 'T'
            $allUsers = $this->_QM->DoCustomQuery($query, $values, true);

            // Loop through all the users to see who has this permission

            //Iterate through all the users
            $approverusermap = array();
        foreach ($allUsers as $user) {
                $extlogindetails = explode("|", $user['LOGINID']);
                $approverusermap[$extlogindetails[1]][$extlogindetails[count($extlogindetails) - 1]] = $user;
        } // for loop ending


            $users = $this->GetTopDownApprovers($approverusermap,  $opid, $ignoreList);

            // Cache the obtained userkey's
            $this->AuthorizedUsersForOPID[$opid]=$users;
            $this->IgnoreListForOPID[$opid] = $ignoreList;

            return $users;
    }

    /**
     * @param array $approverusermap
     * @param int $opid
     * @param array $ignoreList
     *
     * @return array
     */
    function GetTopDownApprovers($approverusermap, $opid, &$ignoreList=array())
    {
        if(empty($approverusermap)) {
                return array();
        }else {
                $parentusers = array();
            foreach  ($approverusermap as $parentCompanyTitle => $loginarray) {

                    $qry = array("SELECT SM.CNY# FROM SCHEMAMAP SM, EXTERNASSOC EXT WHERE SM.TITLE = :1 AND SM.STATUS = 'T' 
                            and SM.CNY# = EXT.EXTERNCNYKEY and EXT.TYPE= 'P' and EXT.LINKED = 'T' and EXT.STATUS = 'T' ", $parentCompanyTitle);
                    $rslt = QueryResult($qry);
                if (!is_array($rslt) || count($rslt) == 0) {
                            continue;
                }
                else {
                            // This else bolck for to get the user details from top level company. Company should be rolebased and m-practice
                    if (IsRoleBasedCny($rslt[0]['CNY#']) && IsPracticeCompany($rslt[0]['CNY#'])) {
                            $result = GetTopDownApproverDetails($rslt[0]['CNY#'], GetMyCompany(), array_keys($loginarray));
                            //eppp_p($result);
                    } else {
                        continue;
                    }
                }    // else end
                foreach  ( $result as $parentloginid) {
                        $perms = INTACCThex2bin($parentloginid['PERMISSIONS']);
                    if (get_bit($perms, $opid)) {
                            $parentusers[] = $loginarray[$parentloginid['LOGINID']];
                    }
                        $ignoreList[] = "'".$loginarray[$parentloginid['LOGINID']]['LOGINID']."'";
                }

            } // for loop end
        }
            return $parentusers;

    }

    /**
     * @return string
     */
    protected function GetApproveOperationKey()
    {
        return 'po/activities/approvepurchases';
    }

    /**
     * @param mixed $systemApprovers
     *
     * @return mixed
     */
    public static function convertSystemApproversToExternalLabels(mixed $systemApprovers)
    {
        $retVals = $systemApprovers;
        if (is_array($retVals)) {
            $dbTokensHandler = DBTokensHandler::getInstance();
            foreach ($retVals as &$systemApprover) {
                $systemApprover['PICKID'] = $dbTokensHandler->getExternalLabel($systemApprover['PICKID']);
            }
            unset($systemApprover);
        }
        return $retVals;
    }

}


