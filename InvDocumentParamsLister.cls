<?
import('NLister');

/**
 * Class InvDocumentParamsLister
 */
class InvDocumentParamsLister extends DocumentParamsLister
{
    /**
     * Returns the title of the Order entry TD lister page.
     *
     * @return string
     *
     * @throws Exception
     */
    protected function getTitle()
    {
        // Force fetch, since this is called in the DocumentParamsLister constructor, before its parent constructor :-(
        return I18N::getSingleToken('IA.TRANSACTION_DEFINITIONS_INVENTORY_CONTROL', [], true);
    }

    /**
     * Returns the name of the Order entry TD entity.
     *
     * @return string
     *
     * @throws Exception
     */
    protected function getEntityName()
    {
        return 'invdocumentparams';
    }

    /**
     * Returns the name of the help file available on the page.
     *
     * @return string
     *
     * @throws Exception
     */
    protected function getHelpFileName()
    {
        return 'Viewing_and_Managing_the_Transaction_Definition_List_for_Inventory';
    }

    /**
     * Returns the Inventory recurring document operation key.
     *
     * @return string
     */
    function getRecurOperationKey() {
        return 'inv/lists/invrecurdocument';
    }

}
