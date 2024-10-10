<?php
/**
 * Utility class implementing methods used by transaction definition setup
 * and transaction setup classes.
 *
 * All methods are static.
 *
 * @author    Samvel Mirijanyan <smirijanyan@intacct.com>
 * @copyright 2000-2015 Intacct Corporation All, Rights Reserved
 */

class DocumentSetupUtil
{
    //FIXME : Fix it for List Card where mod is dashboard !
    /** @var string[]  $MODULE_MAP1*/
    private static $MODULE_MAP1 = ['so' => 'S', 'po' => 'P', 'inv' => 'I'];

    /** @var string[] $MODULE_MAP2 */
    private static $MODULE_MAP2 = ['S' => '8.SO', 'P' => '9.PO', 'I' => '7.INV'];


     /** @var array $permDocParsCache */
    private static $permDocParsCache= array();


    /**
     * @param string $mod can be in the form of 'so', 'po', 'inv', or 'S', 'P', 'I'
     *
     * @return array
     */
    public static function GetNoAddTDs($mod)
    {
        $res = [];
        $modKey = $mod;
        if (isset(self::$MODULE_MAP1[$mod])) {
            $mod = self::$MODULE_MAP1[$mod];
        }
        $docpars = self::GetTrxDefinitionsByMod($mod);
        foreach ($docpars as $docpar) {
            if (! self::isDocparCreatable($docpar, $modKey)) {
                $res[] = $docpar;
            }
        }
        return $res;
    }

    /**
     * @param string   $doctype
     * @param string  $mod
     *
     * @return bool
     *
     */
    public static function isDocTypeCreatableForLoggedInUser($doctype, $mod)
    {
        //If we don't have the passed in info, we treat it as NOT createable
        if ( ! $doctype || ! $mod || ! isset(self::$MODULE_MAP1[$mod]) ) {
            return false;
        }

        $mod = self::$MODULE_MAP1[$mod];

        $arrExplode = explode('@', Globals::$g->_userid);
        $userkey = array_shift($arrExplode);
        if ( ! isset(self::$permDocParsCache[$mod]) ) {
            $docPars = self::GetTrxDefinitionsByMod($mod);
            $allowedDocs = upermFilterResult($docPars, $userkey);
            foreach ( $allowedDocs as $docPar ) {
                self::$permDocParsCache[$mod][] = $docPar['DOCID'];
            }
        }

        $ok= false;
        if (!is_null(self::$permDocParsCache[$mod])){
            $ok= is_array(self::$permDocParsCache[$mod]) ?
                in_array($doctype, self::$permDocParsCache[$mod])
                : $doctype ===self::$permDocParsCache[$mod] ;
        }
        return $ok;

    }

    /**
     * @param array   $docpar
     * @param string  $mod
     *
     * @return bool
     *
     * * Checks if the TD can be used for creating a transaction. It returns
     * false in the following cases:
     * 1. The TD is configured as Convert Only
     * 2. The user is logged in into the root company:
     *    - TD creation rule is not set to either Root and Entity (A)
     *      not to Root (R)
     * 3. The user is logged in into the Entity:
     *    - TD creation rule is not set to Root and Entity (A)
     *      and Entity creation rule is not set to 'true'
     *
     */


    public static function isDocparCreatable($docpar, $mod)
    {
        if (is_null($mod)) {
            throw new InvalidArgumentException(
                "DocumentSetupUtil::isDocparCreatable: Required mod parameter is not provided.");
        }
        $entityPropEntity = $mod . 'documentparentityprop';
        $retVal = true;

        if ($docpar['CREATE_TYPE'] == 'C') {
            // Docpar is not creatable if is configured to be Convert Only
            $retVal = false;
        } else {
            // If not convert only check for creation rule

            // warehouse transfer out should not be allowed to create directly
            if (
                $docpar['DOCID'] == ICTransferManager::OUTDOCTYPE
                || $docpar['DOCID'] == ICTransferManager::INTRANSITDOCTYPE
                || $docpar['DOCID'] == InvDocumentManager::LANDEDCOSTDOCTYPE
                || $docpar['DOCID'] == InvDocumentManager::LANDEDCOSTESTDOCTYPE
                || $docpar['DOCID'] == InvDocumentManager::LANDEDCOSTESTREVDOCTYPE
                || $docpar['DOCID'] == InvDocumentManager::LANDEDCOSTESTREVDOCTYPE
                || $docpar['DOCID'] == ICCycleCountManager::ADJINCREASEDOCTYPE
                || $docpar['DOCID'] == ICCycleCountManager::ADJDECREASEDOCTYPE
                || $docpar['DOCID'] == ICCycleCountManager::ADJDAMAGEDDOCTYPE
                || $docpar['DOCID'] == SODocumentManager::FULFILLMENTINVOICEDOCTYPE
                || $docpar['DOCID'] == SODocumentManager::FULFILLMENTSHIPPERDOCTYPE
                || $docpar['DOCID'] == PODocumentManager::DEFAULTPOAUTOMATIONDOCTYPE
            ) {
                $retVal = false;
            } else if (!isArrayValueProvided($docpar, 'CREATION_RULE')) {
                // Legacy TD, No creation rule is specified
                $retVal = true;
            } else {
                $location = GetContextLocation();
                $isLoggedInToEntity = IsMultiEntityCompany() && $location;
                if ($isLoggedInToEntity) {
                    // Logged in to the entity
                    if ('E' !== $docpar['CREATION_RULE'] && 'A' !== $docpar['CREATION_RULE']) {
                        // Creation rule is set to Top level Only
                        $retVal = false;
                    } else {
                        global $gManagerFactory;
                        /** @var DocumentParEntityPropManager $entityPropertyManager */
                        $entityPropertyManager = $gManagerFactory->getManager($entityPropEntity);
                        $recordCount =
                            $entityPropertyManager->getEntityCountWithProperties($docpar['RECORD#']);
                        if ($recordCount == 0) {
                            // If there is no entity with the specific properties for
                            // the selected TD consider the txn creatable
                            $retVal = true;
                        } else {
                            $entityProperties =
                                $entityPropertyManager->getEntityProperties($docpar['RECORD#'], $location);
                            if (!$entityProperties || 'true' != $entityProperties['ENTITY_CREATION_RULE']) {
                                $retVal = false;
                            }
                        }

                    }
                } else {
                    // Logged in to the root
                    $retVal = ('R' === $docpar['CREATION_RULE'] || 'A' === $docpar['CREATION_RULE']);
                }
            }
        }
        return $retVal;
    }

    /**
     * @param string $mod
     * @param string $docclass
     * @param string $category
     * @param bool   $activeOnly
     *
     * @return string[][]|false
     */
    public static function GetTrxDefinitionsByMod($mod, $docclass = "", $category = "", $activeOnly = false)
    {
        if (!isset($mod)) {
            throw new InvalidArgumentException(
                "DocumentSetupUtil::GetTrxDefinitionsByMod: Required mod parameter is not provided.");
        }

        if (!isset(self::$MODULE_MAP2[$mod])) {
            throw new InvalidArgumentException(
                "DocumentSetupUtil::GetTrxDefinitionsByMod: Invalid mod parameter ($mod).");
        }

        $gQueryMgr = Globals::$g->gQueryMgr;
        $atEntity = IsMultiEntityCompany() && GetContextLocation();

        // Key for the cached query results. It is entity specific and
        // will be prefixed by entity id if logged in into entity.
        $cacheKey = $mod.$docclass.$category.$activeOnly.'DocumentParams';
        
        if ($atEntity) {
            $cacheKey = $cacheKey.'_'.GetContextLocation();
        }

        /* @var string[][][]|false[] $docparCache */
        static $docparCache = [];
        if (isset($docparCache[$cacheKey])) {
            return $docparCache[$cacheKey];
        }

        $qryKey = 'QRY_DOCUMENTPARAMS_SELECT_BY_MOD_' . $mod;
        $cny = GetMyCompany();
        $ret = array();
        $filter = "";
        $argTypes = array('integer', 'text');
        $args = array($cny, $mod);
        if (isset($docclass) && "" !== $docclass) {
            $filter = $filter . " AND docclass in ('".$docclass."') ";
            $argTypes[] = 'text';
            $qryKey .= '_DC';
        }
        if (isset($category) && "" !== $category) {
            $filter = $filter . " AND category = ? ";
            $args[] = $category;
            $argTypes[] = 'text';
            $qryKey .= '_CAT';
        }

        if ($activeOnly) {
            $filter = $filter . " AND status = 'T' ";
            $qryKey .= '_ST';
        }

        if ($atEntity) {
            $qryKey .= '_' . GetContextLocation();
        }

        $args[] = $cny;
        $args[] = self::$MODULE_MAP2[$mod];
        $argTypes[] = 'integer';
        $argTypes[] = 'text';

        $entityCondition = self::getEntityCondition($argTypes, $args, self::$MODULE_MAP2[$mod]);

        // Get all the documents
        $kmyQuery[$qryKey] = array(
            'QUERY' => "SELECT mp.docrecord#, mp.order#, docpar.record#, docpar.docid, " .
                       "   docpar.userperm, docpar.psaimport, docpar.category, " .
                       "   docpar.updinv, docpar.updgl, docpar.status, docpar.locationkey, " .
                       "   docpar.enablerevrec, docpar.posttogl, docpar.docclass, docpar.enable_costing, " .
                       "   docpar.enablerenewals, docpar.create_type, docpar.creation_rule, " .
                       "   docpar.enableaddinfoscope, docpar.enableaddinfoschedule, docpar.enableaddinfointernalref, " .
                       "   docpar.enableaddinfoexternalref, docpar.enableaddinfobond, docpar.enabledocchange, docpar.enablecontractbilling, " .
                       "   docpar.enablefulfillment, docpar.enableallocreserve " .
                       "FROM " .
                       "(SELECT cny#, record#, docid, nvl(updinv,'F') as updinv, nvl(updgl,'F') as updgl, " .
                       " nvl(userperm, 'F') as userperm, nvl(psaimport, 'F') as psaimport, enable_costing, category, " .
                       " status, locationkey,nvl(enablerevrec,'F') as enablerevrec, " .
                       " nvl(posttogl,'F') as posttogl, docclass, nvl(enablerenewals,'F') as enablerenewals," .
                       " nvl(create_type,'F') as create_type, creation_rule,  " .
                       " enable_scope enableaddinfoscope, enable_schedule enableaddinfoschedule, enable_internalref  enableaddinfointernalref," .
                       " enable_externalref enableaddinfoexternalref, enable_bond enableaddinfobond, enabledocchange enabledocchange," .
                       " enable_contract_billing enablecontractbilling, enablefulfillment, enableallocreserve" .
                       " FROM docpar " .
                       " WHERE latestversionkey is null and cny#=? and sale_pur_trans=? " . $filter . ") docpar " .
                       " LEFT OUTER JOIN " .
                       "(SELECT cny#, property, SUBSTR(property, 11) as docrecord#, to_number(value) as order# " .
                       " FROM MODULEPREF " .
                       " WHERE cny# = ?  and modulekey = ? and property like 'TD_RECORD#%' $entityCondition) mp " .
                       "ON docpar.record# = mp.docrecord# " .
                       "ORDER BY mp.order#, docpar.docid",
            'ARGTYPES' => $argTypes
        );

        if ($gQueryMgr && $cny) {
            $gQueryMgr->LoadQueries($kmyQuery);

            $ret = $gQueryMgr->DoQuery($qryKey, $args);
        }
        $docparCache[$cacheKey] = $ret;
        return $ret;
    }

    /**
     * @param string $mod
     *
     * @return array
     */
    public static function getDocumentParamsAffectsInventory($mod)
    {
        $docs = self::GetTrxDefinitionsByMod($mod, "", "", true);
        $retval = array();
        foreach ( $docs as $doc) {
            if (in_array($doc['DOCID'], array(BUILD_KIT, DIS_KIT))) {
                continue;
            }
            // include the document type only if it affects inventory Value (V) or Quantity & Value (T)
            if ($doc['UPDINV'] == 'V' || $doc['UPDINV'] == 'T') {
                $retval[] = $doc['DOCID'];
            }
        }
        return $retval;
    }

    /**
     * @param array $argTypes
     * @param array $args
     * @param string $mod
     *
     * @return string
     */
    private static function getEntityCondition(&$argTypes, &$args, $mod) 
    {

        if ( IsMultiEntityCompany() && GetContextLocation() && $mod) {
            // check if there is any TD ordering stored for entity
            global $gManagerFactory;
            /*
            $moduleMap = array(
                '8.SO' => 'sosetup', '9.PO' => 'posetup', '7.INV' => 'invsetup'
            );
            $moduleSetupManager = $gManagerFactory->GetManager($moduleMap[$mod]);
            */
            // @TODO Using cosetup is not correct. Shall use the proper manager.
            $moduleSetupManager = $gManagerFactory->getManager('cosetup');

            $ordinalNumbers = $moduleSetupManager->getPreferencesByPattern('TD_RECORD#', $mod);
            if ($ordinalNumbers && is_array($ordinalNumbers)) {
                $entityCondition = " and locationkey = ? ";
                $args[] = GetContextLocation();
                $argTypes[] = "integer";
            } else {
                $entityCondition = " and locationkey is null ";
            }
        } else {
            $entityCondition = " and locationkey is null ";
        }
        return $entityCondition;
    }

    /**
     * Generates setup info for the collection of documents of the
     * given type (specified by the argument mode).
     *
     * @param string $mod
     * @param bool $all
     *
     * @return array
     */
    public static function GenerateDocumentSetupInfo($mod, $all = false) 
    {
        $ret = self::GetTrxDefinitionsByMod($mod);
        $modMgr = Globals::$g->gManagerFactory->getManager('modules');
        $invModuleSubscribed = $modMgr->isModuleSubscribed(Globals::$g->kINVid);

        if (is_array($ret) && count($ret) > 0) {
            foreach($ret as $row) {
                if (!$all) {
                    if ($row['STATUS'] == 'F' ) {
                        continue;
                    }
                }
                $doc = $row['DOCID'];
                $lockey = $row['LOCATIONKEY'];
                $doc4path = str_replace(' ', '_', $row['DOCID']);

                if ($row['UPDINV'] != 'F' || $row['POSTTOGL'] == 'T' || ($row['UPDGL'] == 'A' || $row['UPDGL'] == 'G')) {
                    $info[] = array (
                        'path'      =>  'DOCUMENT.'.$doc4path.'_BATCH',
                        'fullname'  =>  $doc . ': ' . _("Summary period"),
                        'desc'      =>  "$doc: Summary Period",
                        'default'   => "Daily",
                        'location'  => $lockey,
                        'document'  => "YES",
                        'type'      =>  array (
                            'ptype'         =>  'enum',
                            'type'          =>  'enum',
                            'validlabels' => array(
                                _('Each document'),
                                _('Daily'),
                                _('Monthly')
                            ),
                            'validvalues'   => array(
                                'Each Document','Daily','Monthly'
                            ),
                            '_validivalues' => array('E','D','M'),
                        )
                    );
                    if (($mod != 'P' && $row['UPDINV'] != 'F')
                        || ($mod == 'P' && $row['POSTTOGL'] == 'T')
                        || ($row['ENABLE_COSTING'] == 'T' && !$invModuleSubscribed)) {
                        $info[] = array (
                            'path'      =>  'DOCUMENT.'.$doc4path.'_JOURNAL',
                            'fullname'  =>  $doc . ': ' . _('Inventory journal'),
                            'desc'      =>  "$doc: Inventory Journal",
                            'location'  => $lockey,
                            'document'  => "YES",
                            'type'      =>  array (
                                'ptype'     =>  'ptr',
                                'type'      =>  'ptr',
                                'size'      =>  4,
                                'maxlength' =>  4,
                                'entity'    =>  'journal',
                            )
                        );
                    }
                    if ($mod == 'S' && $row['POSTTOGL'] == 'T') {
                        $info[] = array (
                            'path'      =>  'DOCUMENT.'.$doc4path.'_ADDJOURNAL',
                            'fullname'  =>  $doc . ': ' . _('Additional posting journal'),
                            'desc'      =>  "$doc: Additional posting journal",
                            'location'  => $lockey,
                            'document'  => "YES",
                            'type'      =>  array (
                                'ptype'     =>  'ptr',
                                'type'      =>  'ptr',
                                'size'      =>  4,
                                'maxlength' =>  4,
                                'entity'    =>  'journal',
                            )
                        );
                    }
                    if ($row['ENABLEREVREC'] != 'F') {
                        $info[] = array (
                            'path'      =>  'DOCUMENT.'.$doc4path.'_REVRECJOURNAL',
                            'fullname'  =>  $doc . ': ' . _('Rev rec journal'),
                            'desc'      =>  "$doc:  Rev Rec Journal",
                            'location'  => $lockey,
                            'document'  => "YES",
                            'type'      =>  array (
                                'ptype'     =>  'ptr',
                                'type'      =>  'ptr',
                                'size'      =>  4,
                                'maxlength' =>  4,
                                'entity'    =>  'journal',
                            )
                        );
                    }
                    if ($row['ENABLEREVREC'] != 'F') {
                        $info[] = array (
                            'path'      =>  'DOCUMENT.'.$doc4path.'_DEFREVACCT',
                            'fullname'  =>  $doc . ': ' . _('Default deferred revenue account'),
                            'desc'      =>  "$doc: Default Deferred Revenue Account",
                            'location'  => $lockey,
                            'document'  => "YES",
                            'type'      =>  array (
                                'ptype'     =>  'ptr',
                                'type'      =>  'ptr',
                                'size'      =>  24,
                                'maxlength' =>  24,
                                'entity'    =>  'glaccount',
                                'pickentity'    =>  'glaccountpick',
                            )
                        );
                    }
                    // Batch period for direct posting to GL
                    if( $row['UPDGL'] == 'G') {
                        if ( $mod == 'P' || $mod == 'S' ) {
                            $desc2 = '';

                            if ( $mod == 'S' ) {
                                $fullname2 = $doc . ': ' . _('Sales journal');
                                $desc2 = "$doc: Sales Journal";
                            } elseif ( $mod == 'P' ) {
                                $fullname2 = $doc . ': ' . _('Purchase Journal');
                                $desc2 = "$doc: Purchase Journal";
                            }

                            /** @noinspection PhpUndefinedVariableInspection */
                            $info[] = array (
                                'path'  =>  'DOCUMENT.'.$doc4path.'_PRINVJOURNAL',
                                'fullname'  =>  $fullname2,
                                'desc'  =>  $desc2,
                                'location'  => $lockey,
                                'document'  => "YES",
                                'type'  =>  array (
                                    'ptype' =>  'ptr',
                                    'type'  =>  'ptr',
                                    'size'  =>  4,
                                    'maxlength' =>  4,
                                    'entity'    =>  'journal',
                                )
                            );

                        }
                    }

                    // Add email template info
                    $info[] = [
                        'path'  =>  'DOCUMENT.'.$doc4path.'_EMAILTEMPLATE',
                        'fullname'  =>  $doc . ': ' . _('Email Template'),
                        'desc'      =>  $doc . ': Email Template',
                        'location'  => $lockey,
                        'document'  => 'YES',
                        'type'  =>  [
                            'ptype' =>  'ptr',
                            'type'  =>  'ptr',
                            'size'  =>  4,
                            'maxlength' =>  4,
                            'entity'    =>  'emailtemplate',
                        ]

                    ];
                    // Add Print Format info
                    $info[] = [
                        'path'  =>  'DOCUMENT.'.$doc4path.'_XSLTEMPLATE',
                        'fullname'  =>  $doc . ': ' . _('Document template'),
                        'desc'      =>  $doc . ': Document template',
                        'location'  => $lockey,
                        'nopick'	=> false,
                        'noedit' => true,
                        'nonew' => true,
                        'noview' => false,
                        'type'  =>  [
                            'ptype' 	=> 'ptr',
                            'type' 		=> 'ptr',
                            'entity' 	=> 'tplformat',
                            'size'		=> 20,
                            'maxlength'	=> 100,
                            'pickfield' => array('DESCRIPTION', 'MODULEID', 'DOCTYPE', 'RECORDNO'),
                        ]
                    ];

                }
            }
        }

        /** @noinspection PhpUndefinedVariableInspection */
        return $info;
    }

    /**
     *  Generates setup schema for the collection of documents of the
     * given type (specified by the argument mode).
     *
     * @param string $mod
     *
     * @return array
     */
    public static function GenerateDocumentSetupSchema($mod)
    {

        $ret = self::GetTrxDefinitionsByMod($mod);

        $schema = array ( );
        $temp   = array ( );
        if ($ret !== false && count($ret) > 0) {
            $modMgr = Globals::$g->gManagerFactory->getManager('modules');
            $invModuleSubscribed = $modMgr->isModuleSubscribed(Globals::$g->kINVid);

            foreach($ret as $row) {
                if ($row['STATUS'] == 'F' ) {
                    continue;
                }
                $doc4path = str_replace(' ', '_', $row['DOCID']);
                if ($row['UPDINV'] != 'F' || $row['POSTTOGL'] == 'T' 
                    || ($row['UPDGL'] == 'A' || $row['UPDGL'] == 'G')
                ) {
                    $temp[$doc4path.'_BATCH'] = 'dummy';
                    if (($mod != 'P' && $row['UPDINV'] != 'F')
                        || ($mod == 'P' && $row['POSTTOGL'] == 'T')
                        || ($row['ENABLE_COSTING'] == 'T' && !$invModuleSubscribed) ) {
                        $temp[$doc4path.'_JOURNAL'] = 'dummy';
                    }

                    if ($mod == 'S' && $row['POSTTOGL'] == 'T') {
                        $temp[$doc4path.'_ADDJOURNAL'] = 'dummy';
                    }

                    if ($row['UPDGL'] == 'G') {
                        $temp[$doc4path.'_PRINVJOURNAL'] = 'dummy';
                    }

                    if ($row['ENABLEREVREC'] == 'T') {
                        $temp[$doc4path.'_REVRECJOURNAL'] = 'dummy';
                        $temp[$doc4path.'_DEFREVACCT'] = 'dummy';
                    }
                }
                $temp[$doc4path.'_EMAILTEMPLATE'] = 'dummy';
            }
        }
        $schema['DOCUMENT'] = array ( );
        $schema['DOCUMENT'] = $temp;
        return $schema;
    }

}
