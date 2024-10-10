<?

//=============================================================================
//
//	FILE:		DataRetrieverTester.cls
//	AUTHOR:		Odysseas
//
//=============================================================================



import('EntityDataRetriever');
import('EntityManager');
import('ManagerFactory');
import('ProductLineManager');


/**
 * Class ProductLineManagerTester
 */
class ProductLineManagerTester extends TestCase
{
    /** @var ProductLineManager $_ProductLineMgr */
    var $_ProductLineMgr;

    /** @var  array $_infoMap */
    var $_infoMap;

    /** @var string $_idPrefix */
    var $_idPrefix = 'TEST-1973';

    /** @var  string $_cny */
    var $_cny;

    /**
     * @param string $_name
     */
    function __construct($_name)
    {
        parent::__construct($_name);
    }

    /**
     *  Setup()
     */
    function Setup() 
    {
        //global $_userid;
        //i,ii,ii at inv database
        //$_userid='2@1683@A';
        global $gManagerFactory;
        $this->_cny = '1683';

        Sudo('2@'.$this->_cny.'@A', 'prod_owner_02/prodowner2001@dev02');
        parent::setUp();

        $this->_ProductLineMgr = $gManagerFactory->getManager('productline');
        $this->_infoMap =& $this->_ProductLineMgr->GetEntityInfoMap();

    }

    /**
     * @return ProductLineManager
     */
    public function getProdLineMgr()
    {
        return $this->_ProductLineMgr;
    }

    /**
     * TearDown
     */
    function TearDown() 
    {
        ExecSimpleStmt("DELETE FROM icprodline WHERE productlineid like '".$this->_idPrefix."%'  AND cny# =".$this->_cny);
    }

    /**
     * @param string $fld
     *
     * @return string
     */
    function GetMaxLengthInputValue($fld) 
    {
        epp("GetMaxLengthInputValue($fld)");
        $testVals = array (
        'integer'    =>    9,
        'decimal'    =>    9,
        'text'        =>    'Z',
        );
        $max    = $this->_infoMap[$fld]['type']['maxlength'];
        $type    = $this->_infoMap[$fld]['type']['ptype'];
        $value = str_repeat($testVals[$type], $max); 
        epp("returning $value");
        return $value;
    }


    /**
     * testGet_p
     */
    function testGet_p() 
    {
        epp("BEGIN testGet_p");

        $records = DOM::CreateFromString(
            '
<record-list>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'-0</PRODUCTLINEID>
		<PARENTLINE></PARENTLINE>
		<DESCRIPTION>Simple Description</DESCRIPTION>
		<STATUS>active</STATUS>
	</record>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'-1</PRODUCTLINEID>
		<PARENTLINE></PARENTLINE>
		<DESCRIPTION>Simple Description</DESCRIPTION>
		<STATUS>inactive</STATUS>
	</record>
</record-list>
'
        );

        foreach ($records->ToSimplePHP(true) as $record) {
            $ok = $this->getProdLineMgr()->add($record);
            if (!$ok) {
                epp("ProductLineManagerTester::testGet : Add failed");
                eppp($record);
            }
        }
        /** @var EntityDataRetriever $dr */
        $dr = GetDataRetriever(
            DOM::CreateFromString(
                '
<data-retriever id="1" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<connection type="entity" entity="ProductLine"/>
    <column-list> 
		<column name="PRODUCTLINEID" seq="1" />
		<column name="PARENTLINE" seq="2" />
		<column name="DESCRIPTION" seq="3" />
		<column name="STATUS" seq="4" />
	</column-list>
	<filter-list>
		<filter attr="PRODUCTLINEID" op="like" value="'.$this->_idPrefix.'%" seq="1"/>
	</filter-list>
	 <sort-list>
        <sort attr="PRODUCTLINEID" mode="asc" seq="1" />
    </sort-list>
</data-retriever>
'
            )
        );

        $dr->Bind();
        /** @var DOM $result */
        $result = $dr->FetchAllXML();
        $this->assert(
            is_object($result) && $result->Equals($records), 
            'Returned record did not match original.'
        );
        ExecSimpleStmt("DELETE FROM icprodline WHERE productlineid like '".$this->_idPrefix."%'  AND cny# =".$this->_cny);
        epp("END testGet_p");
    }


    /**
     *
     */
    function testParent_p() 
    {
        epp("BEGIN testParent_p");

        $records = DOM::CreateFromString(
            '
<record-list>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'-0</PRODUCTLINEID>
		<PARENTLINE></PARENTLINE>
		<STATUS>active</STATUS>
	</record>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'-1</PRODUCTLINEID>
		<PARENTLINE>'.$this->_idPrefix.'-0</PARENTLINE>
		<STATUS>active</STATUS>
	</record>
</record-list>
'
        );

        foreach ($records->ToSimplePHP(true) as $record) {
            $ok = $this->getProdLineMgr()->add($record);
            if (!$ok) {
                epp("ProductLineManagerTester::testParent_p : Add failed");
                eppp($record);
            }
        }
        /** @var EntityDataRetriever $dr */
        $dr = GetDataRetriever(
            DOM::CreateFromString(
                '
<data-retriever id="1" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<connection type="entity" entity="ProductLine"/>
    <column-list> 
		<column name="PRODUCTLINEID" seq="1" />
		<column name="PARENTLINE" seq="2" />
		<column name="STATUS" seq="4" />
	</column-list>
	<filter-list>
		<filter attr="PRODUCTLINEID" op="like" value="'.$this->_idPrefix.'%" seq="1"/>
	</filter-list>
	 <sort-list>
        <sort attr="PRODUCTLINEID" mode="asc" seq="1" />
    </sort-list>
</data-retriever>
'
            )
        );

        $dr->Bind();

        $result = $dr->FetchAllXML();

        $this->assert(
            is_object($result) && $result->Equals($records), 
            'Returned record did not match original.'
        );
        ExecSimpleStmt("DELETE FROM icprodline WHERE productlineid like '".$this->_idPrefix."%'  AND cny# =".$this->_cny);
        epp("END testParent_p");
    }


    /**
     * @return  bool
     */
    function testParent_n() 
    {
        epp("BEGIN testParent_n");

        $records = DOM::CreateFromString(
            '
<record-list>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'-0</PRODUCTLINEID>
		<PARENTLINE></PARENTLINE>
		<STATUS>active</STATUS>
	</record>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'-1</PRODUCTLINEID>
		<PARENTLINE>'.$this->_idPrefix.'-1</PARENTLINE>
		<STATUS>active</STATUS>
	</record>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'-1</PRODUCTLINEID>
		<PARENTLINE>'.$this->_idPrefix.'-2</PARENTLINE>
		<STATUS>active</STATUS>
	</record>
</record-list>
'
        );

        $phpRecords = $records->ToSimplePHP(true);

        $ok = $this->getProdLineMgr()->add($phpRecords[0]);

        $testResult = 1;
        $msg = '';
        if (!$ok) {
            $msg = "ProductLineManagerTester::testParent_n : Add of parent failed.";
            epp($msg);
            eppp($phpRecords[0]);
            $testResult = 0;
        }
        $ok = $this->getProdLineMgr()->add($phpRecords[1]);
        if ($ok) {
            $msg = "ProductLineManagerTester::testParent_n : Add of orphaned ProductLine succeeded.";
            epp($msg);
            eppp($phpRecords[1]);
            $testResult = 0;
        }

        $this->assert($testResult, $msg);

        ExecSimpleStmt("DELETE FROM icprodline WHERE productlineid like '".$this->_idPrefix."%'  AND cny# =".$this->_cny);
        epp("END testParent_n");
        return true;
    }


    function testSet_p() 
    {
        epp("BEGIN testSet_p");
        $source = "ProductLineManagerTester::testSet";

        $records = DOM::CreateFromString(
            '
<record-list>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'</PRODUCTLINEID>
		<DESCRIPTION>Old Description</DESCRIPTION>
	</record>
</record-list>
'
        );
        foreach ($records->ToSimplePHP(true) as $record) {
            $ok = $this->getProdLineMgr()->add($record);
            if (!$ok) {
                epp("ProductLineManagerTester::testSet_p : Add failed");
                eppp($record);
            }
        }

        // this rhashes thing works since there is only one.
        $new_records = $expected_records = DOM::CreateFromString(
            '
<record-list>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'</PRODUCTLINEID>
		<DESCRIPTION>New Description</DESCRIPTION>
	</record>
</record-list>
'
        );

        foreach ($new_records->ToSimplePHP(true) as $new_record) {
            $ok = $this->getProdLineMgr()->set($new_record);
            if (!$ok) {
                epp("$source: Set failed");
                /** @noinspection PhpUndefinedVariableInspection */
                eppp($record);
            }
        }

        /** @var EntityDataRetriever $dr */
        $dr = GetDataRetriever(
            DOM::CreateFromString(
                '
<data-retriever id="1" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<connection type="entity" entity="ProductLine"/>
    <column-list> 
		<column name="PRODUCTLINEID" seq="1" />
		<column name="DESCRIPTION" seq="2" />
	</column-list>
	<filter-list>
		<filter attr="PRODUCTLINEID" op="like" value="'.$this->_idPrefix.'%" seq="1"/>
	</filter-list>
</data-retriever>
		'
            )
        );

        $dr->Bind();

        $result = $dr->FetchAllXML();
        //epp("RESULT");
        //eppp($result->ToSimplePHP());
        //epp("new Items");
        //eppp($expected_records->ToSimplePHP());
        $this->assert(is_object($result) && $result->Equals($expected_records), 'Returned record did not match original.');
        ExecSimpleStmt("DELETE FROM icprodline WHERE productlineid like '".$this->_idPrefix."%'  AND cny# =".$this->_cny);
        /** @noinspection PhpUndefinedVariableInspection */
        if (!$ok) {
            epp('Failed deleting record');
        }
        epp("END testSet_p");
    }


    function testDelete_p() 
    {
        epp("BEGIN testDelete_p");

        $records = DOM::CreateFromString(
            '
<record-list>
	<record>
		<PRODUCTLINEID>'.$this->_idPrefix.'</PRODUCTLINEID>
	</record>
</record-list>
'
        );
        $expected_records = DOM::CreateFromString(
            '
<record-list>
</record-list>
'
        );

        foreach ($records->ToSimplePHP(true) as $record) {
            $ok = $this->getProdLineMgr()->add($record);
            if (!$ok) {
                epp("ProductLineManagerTester::testDelete_p : Add failed");
                eppp($record);
            }
            $ok = $this->getProdLineMgr()->Delete($this->_idPrefix);
            if (!$ok) {
                epp("ProductLineManagerTester::testDelete_p : Delete failed");
                eppp($record);
            }
        }
        /** @var EntityDataRetriever $dr */
        $dr = GetDataRetriever(
            DOM::CreateFromString(
                '
<data-retriever id="1" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<connection type="entity" entity="ProductLine"/>
    <column-list> 
		<column name="PRODUCTLINEID" seq="1" />
	</column-list>
	<filter-list>
		<filter attr="PRODUCTLINEID" op="=" value="'.$this->_idPrefix.'" seq="1"/>
	</filter-list>
</data-retriever>
'
            )
        );

        $dr->Bind();

        $result = $dr->FetchAllXML();
        //epp("RESULT");
        //eppp($result->ToSimplePHP());
        //epp("new Items");
        //eppp($expected_records->ToSimplePHP());
        $this->assert(is_object($result) && $result->Equals($expected_records), 'Returned record did not match original.');

        epp("END testDelete_p");
    }

    /**
     * @return bool
     */
    function testValidateRequired_n() 
    {
        epp("BEGIN testValidateRequired_n");

        $records = DOM::CreateFromString(
            '
<record-list>
	<record>
		<PRODUCTLINEID></PRODUCTLINEID>
	</record>
</record-list>
'
        );

        $success = true;

        $caseNo = 1;
        foreach ($records->ToSimplePHP(true) as $record) {
            $success = $this->getProdLineMgr()->add($record);
            if ($success) {
                epp("ProductLineManagerTester::testValidateRequired_n : Add succeeded where failure was expected. CASE[$caseNo]");
                eppp($record);
            }
            $caseNo++;
        }

        $this->assert(!$success, 'Validation Test Failed.');
        
        if ($success) {
            $ok = $this->getProdLineMgr()->Delete($this->_idPrefix);
            if (!$ok) { 
                epp('Failed deleting record');
            }
        }
        epp("END testValidateRequired_n");
        return true;
    }

    /**
     * @return bool
     */
    function testValidateFormats_n() 
    {
        epp("BEGIN testValidateFormats_n");

        $defaultLength = isl_strlen($this->_idPrefix);
        $padNeeded = intval($this->_infoMap['PRODUCTLINEID']['type']['maxlength']) - $defaultLength;
        $overflowID = $this->_idPrefix . str_repeat('J', $padNeeded+1);

        $IDs = array (
        $overflowID,
        );

        $records = DOM::CreateFromString(
            '
<record-list>
	<record>
		<PRODUCTLINEID>'.$IDs[0].'</PRODUCTLINEID>
	</record>
</record-list>
'
        );

        $success = true;

        $caseNo = 0;
        $failures = array();
        foreach ($records->ToSimplePHP(true) as $record) {
            $success = $this->getProdLineMgr()->add($record);
            $failures[$caseNo] = 0;
            if ($success) {
                $msg ="ProductLineManagerTester::testValidateFormats_n : Add succeeded where failure was expected. CASE[$caseNo]"; 
                epp($msg);
                eppp($record);
                $failures[$caseNo] = 1;
            }
            $caseNo++;
        }

        $this->assert(!$success, 'Invalidat Data inserted.');
        
        if ($success) {
            foreach ($failures as $caseNo => $val) {
                if ($val == 1) {
                    ExecSimpleStmt("DELETE FROM icprodline WHERE productlineid = '".$IDs[$caseNo]."'  AND cny# =".$this->_cny);
                    /** @noinspection PhpUndefinedVariableInspection */
                    if (!$ok) {
                        epp('Failed deleting record');
                   }
                }
            }
        }
        epp("END testValidateFormats_n");
        return true;
    }

}
