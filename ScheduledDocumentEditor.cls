<?php
//
//================================================================================
//	FILE:			ScheduledDocumentEditor.cls
//	AUTHOR:			bharris
//	DESCRIPTION:	Recurring document editor base class.
//					Manager of functionality for scheduling tab used by
//					recurring transaction templates.
//					Some additional changes must be made at the javascript level.
//					see RecurDocumentEditor.cls...
//
//	(C)2005, Intacct Corporation, All Rights Reserved
//
//	This document contains trade secret data that belongs to Intacct
//	corporation and is protected by the copyright laws. Information
//	herein may not be used, copied or disclosed in whole or part
//	without prior written consent from Intacct Corporation.
//================================================================================
//
import('DocumentEditor');

/**
 * Class ScheduledDocumentEditor
 */
class ScheduledDocumentEditor extends DocumentEditor
{

   /** @var  bool $hasStarted */
    var $hasStarted;

    /** @var string $scheduleLayer */
    protected $scheduleLayer = 'Layer2';

    /**
     * The true parent class should be 'Editor' but since PHP4
     * currently does not allow    multiple inheritance we have..
     *
     * @param array $_params
     */
    function __construct($_params)
    {
        $this->isQuixote = QXCommon::isQuixote();
        // TODO: Why are we skipping constructors?
        Editor::__construct($_params);
    }



    /**
     * Displays the value in bold font if state is showview.
     *
     * @param  array $field
     *
     * @return bool
     */
    function CheckEditState($field)
    {
        $rtn = true;
        if ($this->state == 'showview') {
            // display the value this field.
            if (isset($field['value']) && ($field['value'] != '')) {
                $val = $field['value'];
                ?>
              <b class="qx-inline-row-item">
                <?= "$val"; ?>
              </b>
            <?;
            }
            $rtn = false;
        }
        return $rtn;
    }



    /**
     * Setup information in the event of return from error and
     * get Editor class to add value to the params array.
     *
     * @param  array $_params
     *
     * @return array
     */
    function Editor_Expand($_params)
    {
        global $gManagerFactory;

        $entityMgr = $gManagerFactory->getManager($_params['entity']);

        if($this->ProcessErrorRetrivalAction($entityMgr)) {
            $obj = Request::$r->GetCurrentObject();
            Request::$r->_dt = $obj['DOCPARID'];
            $this->_fromError = true;
        }
        else {
            $this->_fromError = false;
        }

        return Editor::Editor_Expand($_params);
    }



    /**
     * Handles specific fields associated to the schedule tab
     * field elements.
     *
     * @param  array $_params (byref)
     *
     */
    function Editor_Instantiate(&$_params)
    {

        Editor::Editor_Instantiate($_params);

        //perform local needs.. here we are making a list of
        //form elements that requires special handling.
        $num_fields = count($_params['allfields']);
        for ($num=0; $num < $num_fields; $num++) {

            // Plug in the id to the tree
            $field =& $_params['allfields'][$num];

            //This is used later in ShowSimpleFieldValue
            if ($field['path'] == 'INTERVAL'
                || $field['path'] == 'ENDDATE'
                || $field['path'] == 'OCCUR'
                || $field['path'] == 'INTERVAL1'
                || $field['path'] == 'INTERVAL2'
                || $field['path'] == 'INTERVAL3'
                || $field['path'] == 'INTERVAL4'
            ) {
                $this->tempfields[$field['path']] = $field;
            }
        }

        $obj = Request::$r->GetCurrentObject();

        $execCount = $obj['EXECCOUNT'];
        if($execCount > 0) {
            $this->hasStarted = true;
        }
        else {
            $this->hasStarted = false;
        }

        if($this->hasStarted) {
            $this->MatchTemplates($_params, array('path' => 'STARTDATE'), $startDateParam);
            $startDateParam[0]['readonly'] = true;

            if($this->state == $this->kShowEditState) {
                $this->MatchTemplates($_params, array('path' => 'NEXTEXECDATE'), $nextExecParam);
                $nextExecParam[0]['readonly'] = false;
            }
        }
    }


    /**
     * Loads object with values used in the display settings on the
     * schedule tab.
     *
     * @param array $values
     *
     * @param bool $isDuplicateOp
     */
    function InitializeDisplayValues( &$values, $isDuplicateOp)
    {
        // Setup schedule tab's display elements...
        /** @noinspection PhpSillyAssignmentInspection */
        $values['STARTDATE'] = $values['STARTDATE'];
        if ($values['ENDDATE'] != '') {
            // end date is specially handled as text field
            $values['ENDDATE'] = ($this->state == 'showview' ? FormatDateForDisplay($values['ENDDATE']) : $values['ENDDATE']);
            $values['ENDING'] = 'End date';
        }
        else {
            if($isDuplicateOp && $values['OCCUR'] != '') {
                $values['ENDING'] = 'Number of occurrences';
            }
            else if ($values['REPEATCOUNT'] != '') {
                if($this->state == 'showview' || $this->state == 'showedit') {
                    $values['ENDING'] = 'Number of occurrences remaining';
                }
                else {
                    $values['ENDING'] = 'Number of occurrences';
                }
                $values['OCCUR'] = $values['REPEATCOUNT'] - $values['EXECCOUNT'];        //No of occurrences is "remain count" (REPEATCOUNT - EXECCOUNT)
            }
            else {
                $values['ENDING'] = 'Never';
            }
        }

        //End of month
        $values['EOM'] = 'false';
        switch ($values['REPEATBY']) {
        case 'N':
            $values['MODENEW'] = 'None';    //This is repeat radio group on second tab
            break;
        case 'D':
            $values['MODENEW'] = 'Days';
            $values['INTERVAL1'] = $values['INTERVAL'];        //Interva1 holds repeat interval for daily frequency
            break;
        case 'W':
            $values['MODENEW'] = 'Weeks';
            $values['INTERVAL2'] = $values['INTERVAL'];
            break;
        case 'M':
            $values['MODENEW'] = 'Months';
            $values['INTERVAL3'] = $values['INTERVAL'];
            break;
        case 'Y':
            $values['MODENEW'] = 'Years';
            $values['INTERVAL4'] = $values['INTERVAL'];
            break;
        case 'E':
            $values['MODENEW'] = 'Months';
            $values['INTERVAL3'] = $values['INTERVAL'];
            $values['EOM'] = 'true';        //Check end of month checkbox
            break;
        default:
            $values['MODENEW'] = 'None';
            $values['INTERVAL'] = '';
        }
    }


    /**
     * This method is called when the user clicks on the
     * edit link of the Recur..Lister display.
     *
     * @param array $_params
     *
     * @return bool
     */
    function ProcessEditAction(&$_params)
    {
        // comming from an error ...the object data should already
        // be available because ProcessErrorRetrivalAction call has
        // been made during Editor_Expand.
        if ($this->_fromError) {
            return false;
        }

        //Get current object loaded by EDITOR Class and
        // process updates for schedule fields....
        parent::ProcessEditAction($_params);
        $obj = Request::$r->GetCurrentObject();
        $this->InitializeDisplayValues($obj, false);
        Request::$r->SetCurrentObject($obj);
        return true;
    }



    /**
     * This method is called when the user clicks on the
     * view link of the Recur...Lister display.
     *
     * @param array $_params
     */
    function ProcessViewAction(&$_params)
    {
        Editor::ProcessViewAction($_params);
        if ($this->state == $this->kErrorState) {
            return;
        }

        //Get current object loaded by EDITOR Class and
        // process updates for schedule fields....
        $obj = Request::$r->GetCurrentObject();
        $this->InitializeDisplayValues($obj, false);
        Request::$r->SetCurrentObject($obj);
    }



    /**
     * Method to allow setup interaction with data or
     * display elements when mode is copy.
     *
     * @param  array $_params
     *
     * @return bool
     */
    function ProcessCopyNewAction(&$_params)
    {
        //restore the previous value before the execution
        $obj =& Request::$r->GetCurrentObject();

        if (isset($obj['OCCUR']) && isset($obj['EXECCOUNT'])) {
            $obj['OCCUR'] = $obj['OCCUR'] + $obj['EXECCOUNT'];
        }

        $this->InitializeDisplayValues($obj, true);

        $obj['NEXTEXECDATE'] = '';

        Request::$r->_edittype = 'duplicate';
        return true;
    }

    /**
     * @param array  $_params
     * @param string $disable
     */
    function ShowDoButtons($_params, $disable = "")
    {
        $dobutton     = $_params['dobutton'];
        $doaction     = $_params['doaction'];

        $cssClass = $this->isQuixote ? 'btn btn-primary' : 'nosavehistory';

        if ($doaction == 'save') {
            if ($dobutton) { ?>
             <INPUT 	class="<?= $cssClass; ?>"
               type="button" id="savebuttid"
               name="savebutton"
               value="<? echo $dobutton;  ?>"
               onclick="if ( beforeSubmitJS() ) {ConfirmMessage()};" disableonsubmit="true">
            <?
            }
        }else {
            if ($dobutton) { ?>
             <INPUT 	id="savebuttid"
               type="button"
               name="savebutton"
               class="<?= $cssClass; ?>"
               value="<? echo $dobutton;  ?>"
               onclick="document.forms[0].<? echo Editor_Action ; ?>.value = '<?  echo $doaction; ?>';
                 if ( beforeSubmitJS() && BeforeSubmit() ) { document.forms[0].submit(); };" disableonsubmit="true">
            <?
            }
        }
    }

    /**
     * @param array $_params
     */
    function ShowCopyButtons($_params)
    {
        $copybutton = $_params['copybutton'];
        $copyaction = $_params['copyaction'];

        $cssClass = $this->isQuixote ? 'btn btn-primary' : 'nosavehistory';

        if($_params['state'] == Editor_ShowViewState) {
            $resetStateJS = "document.forms[0]._state.value = 'showedit'";
            $resetStateJS .= ";document.forms[0]._do.value = 'edit'";
        }

        if ($copybutton) { ?>
         <INPUT type="button" name="savebutton" class="<?= $cssClass; ?>" value="<? echo $copybutton;  ?>" onclick="document.forms[0].<? echo Editor_Action ; ?>.value = '<?  echo $copyaction; ?>';<? /** @noinspection PhpUndefinedVariableInspection */
         echo $resetStateJS;?>; if(BeforeSubmit()){ResetSchedules();document.forms[0].submit();}" disableonsubmit="true">
        <?
        }
    }

    /**
     * @param array $_params
     * @param int $editop
     */
    function ShowEditButtons($_params,$editop)
    {
        $curObj = Request::$r->GetCurrentObject();

        if(isset($curObj['NEXTEXECDATE'])) {
            parent::ShowEditButtons($_params, $editop);
        }
    }


    /**
     * Show Ending on radio button group for Scheduling Tab
     *
     * @param array $field
     */
    function ShowEnding($field)
    {
        global $gWarnOnSaveJS;

        $name = $field['varname'];
        $value = $field['value'];

        //insures that user can not alter settings if
        // in showview mode...
        $disabled = '';
        if ($this->state == 'showview') {
            if ($field['readonly']) {
                $disabled = ' disabled ';
            }
        }

        if (!$value) {
            $value = 'Never';
        }

        if ($this->state == 'showview' || $this->state == 'showedit') {
            $display = array(_('Never'), _('Number of occurrences remaining'), _('End date'));
        } else {
            $display = array(_('Never'), _('Number of occurrences'), _('End date'));
        }

        if ($this->isQuixote) { ?>
            </div>
            <div class="qx-inline-row">
                <div class="form-group qx-inline-row-item">
                    <div class="radio">
                        <input type="radio" name="<?= $name; ?>"
                               onChange="this.form.elements['_obj__ENDING'].value = this.value;CheckOccurrences();<?= $gWarnOnSaveJS ?>"
                               onClick="CheckEndingOn(this);" value="<? echo($display[0]); ?>"
                            <? echo $value == $display[0] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                        <label><? echo($display[0]); ?></label>
                    </div>
                </div>
            </div>
            <div class="qx-inline-row">
                <div class="form-group qx-inline-row-item">
                    <div class="radio">
                        <input type=radio name="<?= $name; ?>"
                               onChange="this.form.elements['_obj__ENDING'].value = this.value;<?= $gWarnOnSaveJS ?>"
                               onClick="javascript:CheckEndingOn(this);"
                               value="<? echo($display[1]); ?>"
                            <? echo $value == $display[1] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                        <label><? echo($display[1]); ?></label>
                    </div>
                </div>
                <div class="form-group qx-inline-row-item">
                <? parent::ShowSimpleFieldValue($this->tempfields['OCCUR']); ?>
                </div>
            </div>
            <div class="qx-inline-row">
                <div class="form-group qx-inline-row-item">
                    <div class="radio">
                        <input type=radio name="<?= $name; ?>"
                               onChange="this.form.elements['_obj__ENDING'].value = this.value;<?= $gWarnOnSaveJS ?>"
                               onClick="javascript:CheckEndingOn(this);"
                               value="<? echo($display[2]); ?>"
                            <? echo $value == $display[2] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                        <label><? echo($display[2]); ?></label>
                    </div>
                </div>
                <?
                if ($this->CheckEditState($this->tempfields['ENDDATE'])) { ?>
                <div class="form-group qx-inline-row-item">
                    <? Editor::ShowSimpleFieldValue($this->tempfields['ENDDATE']); ?>
                </div>
                <? }
                ?>
            </div>
        <? } else { ?>
            <table border=0>
                <tr>
                    <td>
                        <table border="0" cellpadding=2 cellspacing=0>
                            <tr>
                                <td>
                                    <table cellpadding=1>
                                        <tr>
                                            <td>
                                                <input class="noborder"
                                                       type="radio"
                                                       name="<?= $name; ?>"
                                                       onChange="this.form.elements['_obj__ENDING'].value = this.value;CheckOccurrences();<?= $gWarnOnSaveJS ?>"
                                                       onClick="CheckEndingOn(this);"
                                                       value="<? echo($display[0]); ?>"
                                                    <? echo $value == $display[0] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                            </td>
                                            <td nowrap><? echo($display[0]); ?></td>
                                            <td NOWRAP valign="middle"></td>
                                            <td NOWRAP valign="middle"></td>
                                        </tr>

                                        <tr>
                                            <td valign="middle">
                                                <input class="noborder"
                                                       type="radio"
                                                       name="<?= $name; ?>"
                                                       onChange="this.form.elements['_obj__ENDING'].value = this.value;CheckOccurrences();<?= $gWarnOnSaveJS ?>"
                                                       onClick="CheckEndingOn(this);"
                                                       value="<? echo($display[1]); ?>"
                                                    <? echo $value == $display[1] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                            </td>
                                            <td nowrap><? echo($display[1]); ?></td>
                                            <td NOWRAP valign="middle" align="center"></td>
                                            <td NOWRAP valign="middle">
                                                <?
                                                Editor::ShowSimpleFieldValue($this->tempfields['OCCUR']);
                                                ?>
                                            </td>
                                        </tr>

                                        <tr>
                                            <td valign="middle">
                                                <input class="noborder"
                                                       type="radio"
                                                       name="<?= $name; ?>"
                                                       onChange="this.form.elements['_obj__ENDING'].value = this.value;CheckOccurrences();<?= $gWarnOnSaveJS ?>"
                                                       onClick="CheckEndingOn(this);"
                                                       value="<? echo($display[2]); ?>"
                                                    <? echo $value == $display[2] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                            </td>
                                            <td nowrap><? echo($display[2]); ?></td>
                                            <td WRAP valign="middle" align="center">
                                            </td>
                                            <td WRAP valign="middle">
                                                <?
                                                if ($this->CheckEditState($this->tempfields['ENDDATE'])) {
                                                    Editor::ShowSimpleFieldValue($this->tempfields['ENDDATE']);
                                                }
                                                ?>
                                            </td>
                                        </tr>
                                        <tr>
                                    </table>
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
            <?
        }
    }

    /**
     * Adds special handled fields to a temp array
     *
     * @param array  $_field
     * @param string $layout used only in some descendants of Editor class
     * @param bool   $first  used only in some descendants of Editor class
     */
    function ShowFieldsRow(&$_field, $layout = "", $first = false)
    {
        //These fields are being displayed in ShowSimpleFieldValue,
        // they should not be displayed by Editor directly

        if ( in_array($_field['path'], array( 'OCCUR', 'ENDDATE', 'INTERVAL1', 'INTERVAL2', 'INTERVAL3', 'INTERVAL4' )) ) {
            if ( ! $this->tempfields ) {
                $this->tempfields = array();
            }

            $this->tempfields[$_field['path']] = $_field;
        } else {
            parent::ShowFieldsRow($_field);
        }
    }

    /**
     * Show Ending on Frequency group for Scheduling Tab
     * Special layouts
     *
     * @param array $field
     */
    function ShowFrequency($field)
    {
        global $gWarnOnSaveJS;

        $name         = $field['varname'];
        $value         = $field['value'];

        //insures that user can not alter settings if
        // in showview mode...
        $disabled     = '';
        if ($this->state=='showview') {
            if ($field['readonly']) {
                $disabled = ' disabled ';
            }
        }

        if (!$value) {
            $value = 'None';
        }

        $display = array(_('None'), _('Days'), _('Weeks'), _('Months'), _('Years'), _('End of month'));

        ?>
        <input type="hidden" name="<?= $name; ?>" value="<?= $value; ?>"  size=20 >
        <? if ($this->isQuixote) { ?>
            </div>
            <div class="form-group">
                <div class="radio">
                    <input type=radio name="<?= $name; ?>"
                           onChange="this.form.elements['_obj__MODENEW'].value = this.value;<?= $gWarnOnSaveJS ?>"
                           onClick="CheckRepeat(this);"
                           value="<? echo($display[0]); ?>"
                        <? echo $value == $display[0] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                    <label><?= $display[0]; ?></label>
                </div>
            </div>
            <div class="qx-inline-row">
                <div class="form-group qx-inline-row-item">
                    <div class="radio">
                        <input type=radio name="<?= $name; ?>"
                               onChange="this.form.elements['_obj__MODENEW'].value = this.value;<?= $gWarnOnSaveJS ?>"
                               onClick="CheckRepeat(this);"
                               value="<? echo($display[1]); ?>"
                            <? echo $value == $display[1] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                        <label><?= $display[1]; ?></label>
                    </div>
                </div>
                <label class="qx-inline-row-item"><?= _("every"); ?></label>
                <?
                if ($this->CheckEditState($this->tempfields['INTERVAL1'])) { ?>
                <div class="qx-inline-row-item">
                    <? Editor::ShowSimpleFieldValue($this->tempfields['INTERVAL1']); ?>
                </div>
                <? }
                ?>
                <label class="qx-inline-row-item"><?= isl_strtolower($display[1]); ?></label>
            </div>
            <div class="qx-inline-row">
                <div class="form-group qx-inline-row-item">
                    <div class="radio">
                        <input type=radio name="<?= $name; ?>"
                               onChange="this.form.elements['_obj__MODENEW'].value = this.value;<?= $gWarnOnSaveJS ?> "
                               onClick="CheckRepeat(this);"
                               value="<? echo($display[2]); ?>"
                            <? echo $value == $display[2] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                        <label><?= $display[2]; ?></label>
                    </div>
                </div>
                <label class="qx-inline-row-item"><?= _("every"); ?></label>
                <?
                if ($this->CheckEditState($this->tempfields['INTERVAL2'])) { ?>
                    <div class="qx-inline-row-item">
                    <? Editor::ShowSimpleFieldValue($this->tempfields['INTERVAL2']); ?>
                    </div>
                <? }
                ?>
                <label class="qx-inline-row-item"><?= isl_strtolower($display[2]); ?></label>
            </div>
            <div class="qx-inline-row">
                <div class="form-group qx-inline-row-item">
                    <div class="radio">
                        <input type=radio name="<?= $name; ?>"
                               onChange="this.form.elements['_obj__MODENEW'].value = this.value;<?= $gWarnOnSaveJS ?> "
                               onClick="CheckRepeat(this);"
                               value="<? echo($display[3]); ?>"
                            <? echo $value == $display[3] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                        <label><?= $display[3]; ?></label>
                    </div>
                </div>
                <label class="qx-inline-row-item"><?= _("every"); ?></label>
                <?
                if ($this->CheckEditState($this->tempfields['INTERVAL3'])) { ?>
                    <div class="qx-inline-row-item">
                    <? Editor::ShowSimpleFieldValue($this->tempfields['INTERVAL3']); ?>
                    </div>
                <? }
                ?>
                <label class="qx-inline-row-item"><?= isl_strtolower($display[3]); ?></label>
                <div class="form-group qx-inline-row-item">
                    <div class="checkbox one-option">
                        <input type=checkbox name="_VIRTUAL__EOM"
                               onChange="this.form.elements['_obj__EOM'].value = this.form.elements['_VIRTUAL__EOM'].checked; <?= $gWarnOnSaveJS ?>"
                               value="<? echo($display[5]); ?>"
                            <? echo Request::$r->_obj__EOM == 'true' ? 'checked' : ''; ?>  <?= "$disabled" ?>>
                        <label><? echo($display[5]); ?></label>
                    </div>
                </div>
            </div>
            <div class="qx-inline-row">
                <div class="form-group qx-inline-row-item">
                    <div class="radio">
                        <input type=radio name="<?= $name; ?>"
                               onChange="this.form.elements['_obj__MODENEW'].value = this.value;<?= $gWarnOnSaveJS ?> "
                               onClick="CheckRepeat(this);"
                               value="<? echo($display[4]); ?>"
                            <? echo $value == $display[4] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                        <label><?= $display[4]; ?></label>
                    </div>
                </div>
                <label class="qx-inline-row-item"><?= _("every"); ?></label>
                <?
                if ($this->CheckEditState($this->tempfields['INTERVAL4'])) { ?>
                    <div class="qx-inline-row-item">
                    <? Editor::ShowSimpleFieldValue($this->tempfields['INTERVAL4']); ?>
                    </div>
                <? }
                ?>
                <label class="qx-inline-row-item"><?= isl_strtolower($display[4]); ?></label>
            </div>
        <? } else { ?>
        <table border=0>
            <tr>
                <td>
                    <table border="0" cellpadding=2 cellspacing=0>
                        <tr>
                            <td>
                                <table cellpadding=1>

                                    <tr>
                                        <td>
                                            <input class="noborder"
                                                   type="radio"
                                                   name="<?= $name; ?>"
                                                   onChange="this.form.elements['_obj__MODENEW'].value = this.value;CheckInterval(this);<?= $gWarnOnSaveJS ?>"
                                                   onClick="CheckRepeat(this);"
                                                   value="<? echo($display[0]); ?>"
                                                <? echo $value == $display[0] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                        </td>
                                        <td nowrap><? echo($display[0]); ?></td>
                                        <td NOWRAP valign="middle"></td>
                                        <td NOWRAP valign="middle"></td>
                                    </tr>

                                    <tr>
                                        <td valign="middle">
                                            <input class="noborder"
                                                   type="radio"
                                                   name="<?= $name; ?>"
                                                   onChange="this.form.elements['_obj__MODENEW'].value = this.value;CheckInterval(this); <?= $gWarnOnSaveJS ?>"
                                                   onClick="CheckRepeat(this);"
                                                   value="<? echo($display[1]); ?>"
                                                <? echo $value == $display[1] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                        </td>
                                        <td nowrap><? echo($display[1]); ?></td>
                                        <td NOWRAP valign="middle" align="center"> every</td>
                                        <td NOWRAP valign="middle">
                                            <?
                                            if ($this->CheckEditState($this->tempfields['INTERVAL1'])) {
                                                Editor::ShowSimpleFieldValue($this->tempfields['INTERVAL1']);
                                            }
                                            ?>
                                            days
                                        </td>
                                    </tr>

                                    <tr>
                                        <td valign="middle">
                                            <input class="noborder"
                                                   type="radio"
                                                   name="<?= $name; ?>"
                                                   onChange="this.form.elements['_obj__MODENEW'].value = this.value;CheckInterval(this);<?= $gWarnOnSaveJS ?> "
                                                   onClick="CheckRepeat(this);"
                                                   value="<? echo($display[2]); ?>"
                                                <? echo $value == $display[2] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                        </td>
                                        <td nowrap><? echo($display[2]); ?></td>
                                        <td WRAP valign="middle" align="center"> every
                                        </td>
                                        <td WRAP valign="middle">
                                            <?
                                            if ($this->CheckEditState($this->tempfields['INTERVAL2'])) {
                                                Editor::ShowSimpleFieldValue($this->tempfields['INTERVAL2']);
                                            }
                                            ?>
                                            weeks
                                        </td>
                                    </tr>
                                    <tr>
                                        <td valign="middle">
                                            <input class="noborder"
                                                   type="radio"
                                                   name="<?= $name; ?>"
                                                   onChange="this.form.elements['_obj__MODENEW'].value = this.value;CheckInterval(this);<?= $gWarnOnSaveJS ?>"
                                                   onClick="CheckRepeat(this);"
                                                   value="<? echo($display[3]); ?>"
                                                <? echo $value == $display[3] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                        </td>
                                        <td nowrap><? echo($display[3]); ?></td>
                                        <td NOWRAP valign="middle" align="center"> every</td>
                                        <td NOWRAP valign="middle">
                                            <?
                                            if ($this->CheckEditState($this->tempfields['INTERVAL3'])) {
                                                Editor::ShowSimpleFieldValue($this->tempfields['INTERVAL3']);
                                            }
                                            ?>
                                            months&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<? echo($display[5]); ?>
                                            <input class="noborder" type=checkbox name="_VIRTUAL__EOM"
                                                   onChange="this.form.elements['_obj__EOM'].value = this.form.elements['_VIRTUAL__EOM'].checked; <?= $gWarnOnSaveJS ?>"
                                                   value="<? echo($display[5]); ?>"
                                                <? echo Request::$r->_obj__EOM == 'true' ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                        </td>
                                    </tr>
                                    <tr>
                                        <td valign="middle">
                                            <input class="noborder"
                                                   type="radio"
                                                   name="<?= $name; ?>"
                                                   onChange="this.form.elements['_obj__MODENEW'].value = this.value;CheckInterval(this);<?= $gWarnOnSaveJS ?> "
                                                   onClick="CheckRepeat(this);"
                                                   value="<? echo($display[4]); ?>"
                                                <? echo $value == $display[4] ? 'checked' : ''; ?> <?= "$disabled" ?>>
                                        </td>
                                        <td nowrap><? echo($display[4]); ?></td>
                                        <td NOWRAP valign="middle" align="center"> every</td>
                                        <td NOWRAP valign="middle">
                                            <?
                                            if ($this->CheckEditState($this->tempfields['INTERVAL4'])) {
                                                Editor::ShowSimpleFieldValue($this->tempfields['INTERVAL4']);
                                            }
                                            ?>
                                            years
                                        </td>
                                    </tr>

                                </table>
                            </td>
                        </tr>
                    </table>
                </td>
            </tr>
        </table>
        <?
        }
    }


    /**
     * Add Javascript and CSS to the page.  Subclasses really should call back to their parent.
     *
     * @param bool $addYuiCss include the YUI css files
     */

    function showScripts($addYuiCss = true)
    {
        include_once 'js_dates.inc';
        showJsDates();
        parent::showScripts($addYuiCss);

        ?>
     <!--<script src="../resources/js/documenteditor.js"></script>-->
     <script type="text/javascript" language="JavaScript" >
     <!--

     function doEdit(rec,it,editop,sess,done) {
        <?
        $doctype = Request::$r->_dt;
        ?>
      url = "editor.phtml?.r="+rec+"&.it="+it+"&.do=edit&.op="+editop+"&.dt=<?=$doctype?>&.sess="+sess+"&.done="+done;
      location.href = url;
     }

     function CheckOccurrences() {
      var occur = document.forms['<?php echo $this->scheduleLayer; ?>_form'].elements['_obj__OCCUR'];
      if (occur.value < 0 ) {
				alert('Occurrences can not be negative');
      }
      if (Math.abs(Math.round(occur.value) - occur.value) > 0) {
				alert('Please enter whole number value');
      }
      var enddate = document.forms['<?php echo $this->scheduleLayer; ?>_form'].elements['_obj__ENDDATE'];
      if (enddate.value != '' && occur.value != '') {
				alert('Can not specify both number of occurrences and end date');
      }
     }

     function CheckInterval(val) {
      var interval = val.value;
      if (interval < 0 ) {
				alert('Repeat interval can not be negative');
      }
      if (Math.abs(Math.round(interval) - interval) > 0) {
				alert('Please enter whole number value');
      }
     }


     function ConfirmMessage() {
         document.forms[0].<? echo Editor_Action; ?>.value = 'save';
         if (BeforeSubmit()) {
             document.forms[0].submit();
         }
     }

     function ResetSchedules() {
         //reset values for the scheduler before sending duplicating request to the backend
         document.forms[0].elements['_obj__LASTEXECDATE'].value = '';
         document.forms[0].elements['_obj__NEXTEXECDATE'].value = '';

         //we only need to adjust for OCCUR if it has a value, otherwise, keep it blank/empty.
         if (document.forms[0].elements['_obj__OCCUR'].value != '') {
             document.forms[0].elements['_obj__OCCUR'].value = parseInt(document.forms[0].elements['_obj__OCCUR'].value)
                 + parseInt(document.forms[0].elements['_obj__EXECCOUNT'].value);
         }

         document.forms[0].elements['_obj__EXECCOUNT'].value = '';
         document.forms[0].elements['_obj__ENDING'].value = 'Number of occurrences';
     }

     function CheckEndingOn(var1) {
      var1.form.elements['_obj__ENDING'].value = var1.value;
            if(mode == 'shownew')
            {
                if (var1.value != 'Number of occurrences') {
                    var1.form.elements['_obj__OCCUR'].value = '';
                }
            }
            else
            {
                if (var1.value != 'Number of occurrences remaining') {
                    var1.form.elements['_obj__OCCUR'].value = '';
                }
            }
		    if (var1.value != 'End Date') {
		        var1.form.elements['_obj__ENDDATE'].value = '';
		    }
     }

     function CheckRepeat(var2) {
      var2.form.elements['_obj__MODENEW'].value = var2.value;
      var2.form.elements['_obj__REPEATBY'].value = var2.value;
      var occurval = var2.form.elements['_obj__OCCUR'].value;
      if (var2.value == 'None' && occurval != '1') {
			    alert('If Repeat is none, Can only specify 1 for number of occurrences.');
      }
      //Clear unrelated values and fill up required ones
      switch (var2.value) {
				case 'None': {
					var2.form.elements['_obj__INTERVAL1'].value = '';
					var2.form.elements['_obj__INTERVAL2'].value = '';
					var2.form.elements['_obj__INTERVAL3'].value = '';
					var2.form.elements['_obj__INTERVAL4'].value = '';
			        var2.form.elements['_obj__INTERVAL'].value = '';
				    var2.form.elements['_VIRTUAL__EOM'].checked = false;
					break;
					}
				case 'Days': {
					var2.form.elements['_obj__INTERVAL2'].value = '';
					var2.form.elements['_obj__INTERVAL3'].value = '';
					var2.form.elements['_obj__INTERVAL4'].value = '';
			        var2.form.elements['_obj__INTERVAL'].value = var2.form.elements['_obj__INTERVAL1'].value;
				    var2.form.elements['_VIRTUAL__EOM'].checked = false;
					break;
					}
				case 'Weeks': {
					var2.form.elements['_obj__INTERVAL1'].value = '';
					var2.form.elements['_obj__INTERVAL3'].value = '';
					var2.form.elements['_obj__INTERVAL4'].value = '';
			        var2.form.elements['_obj__INTERVAL'].value = var2.form.elements['_obj__INTERVAL2'].value;
				    var2.form.elements['_VIRTUAL__EOM'].checked = false;
					break;
					}
				case 'Months': {
					var2.form.elements['_obj__INTERVAL1'].value = '';
					var2.form.elements['_obj__INTERVAL2'].value = '';
					var2.form.elements['_obj__INTERVAL4'].value = '';
			        var2.form.elements['_obj__INTERVAL'].value = var2.form.elements['_obj__INTERVAL3'].value;
					break;
					}
				case 'Years': {
					var2.form.elements['_obj__INTERVAL1'].value = '';
					var2.form.elements['_obj__INTERVAL2'].value = '';
					var2.form.elements['_obj__INTERVAL3'].value = '';
			        var2.form.elements['_obj__INTERVAL'].value = var2.form.elements['_obj__INTERVAL4'].value;
				    var2.form.elements['_VIRTUAL__EOM'].checked = false;
					break;
					}
      }
      var2.form.elements['_obj__EOM'].value = var2.form.elements['_VIRTUAL__EOM'].checked;
     }

     //should be called in child class's BeforeSubmit script call
     // see RecurDocumentEditor::showScripts()
     function ProcessScheduledValues() {
      var tmpval1 = '';
      var tmpval2 = '';

      for (var k=1; k<document.forms.length; k++) {
				for (var m=0; m<document.forms[k].elements.length; m++) {
					var cur = document.forms[k].elements[m];
					var curname = cur.name;
					var curval = cur.value;

					if ((curname == '_obj__ENDING') && (cur.checked)) {
						tmpval1 = curval;
					}
					if ((curname == '_obj__MODENEW') && (cur.checked)) {
						tmpval2 = curval;
					}
				}
      }
      //This is done to populate values of radio button group since all of them have same name
      document.forms[0].elements['_obj__ENDING'].value = tmpval1;
      document.forms[0].elements['_obj__MODENEW'].value = tmpval2;
      document.forms[0].elements['_obj__EOM'].value = document.forms['<?php echo $this->scheduleLayer; ?>_form'].elements['_VIRTUAL__EOM'].checked;
     }

     //-->
     </script>
        <?
    }



    /**
     * Constructs special layout for radio buttons
     * group Ending on and Repeat Frequency
     *
     * @param array $_field
     */
    function ShowSimpleFieldValue(&$_field)
    {
        // Special processing for repeat group of checkboxes to
        // show text boxes and radio buttons in one line
        if($_field['path'] == 'MODENEW') {
            $this->ShowFrequency($_field);
        }
        else {
            //Same here
            if ($_field['path'] == 'ENDING') {
                $this->ShowEnding($_field);
            }
            else {
                if (       $_field['path'] != 'INTERVAL1'
                    && $_field['path'] != 'INTERVAL2'
                    && $_field['path'] != 'INTERVAL3'
                    && $_field['path'] != 'INTERVAL4'
                ) {
                    //Bypass ShowSimpleFieldValue() for these 4 fields
                    parent::ShowSimpleFieldValue($_field);
                }
            }
        }
    }

}

