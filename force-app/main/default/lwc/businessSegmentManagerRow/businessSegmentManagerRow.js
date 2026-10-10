import { LightningElement, api, track } from 'lwc';

export default class BusinessSegmentManagerRow extends LightningElement {
    @api cycleOptions = [];
    @api isNew = false;

    @track editing = false;
    @track draft = {};
    _record = {};

    @api
    get record() {
        return this._record;
    }
    set record(val) {
        this._record = val || {};
        if (this.isNew) {
            this.editing = true;
            this.draft = { ...this._record };
        }
    }

    connectedCallback() {
        if (this.isNew) {
            this.editing = true;
            this.draft = { ...this._record };
        }
    }

    get displayBusiness() {
        return this._record.Business__c || '—';
    }

    get displayCycle() {
        return this._record.Cycle__c || '—';
    }

    get isReadMode() {
        return !this.editing;
    }

    get isEditMode() {
        return this.editing;
    }

    handleEdit() {
        this.draft = { ...this._record };
        this.editing = true;
    }

    handleCancel() {
        if (this.isNew) {
            this.dispatchEvent(new CustomEvent('cancel'));
        } else {
            this.editing = false;
        }
    }

    handleFieldChange(e) {
        const field = e.target.dataset.field;
        const value = e.detail ? e.detail.value : e.target.value;
        this.draft = { ...this.draft, [field]: value };
    }

    handleSave() {
        this.dispatchEvent(new CustomEvent('save', { detail: { ...this.draft } }));
        if (!this.isNew) {
            this._record = { ...this._record, ...this.draft };
            this.editing = false;
        }
    }

    handleDelete() {
        // eslint-disable-next-line no-alert
        if (window.confirm(`Delete "${this._record.Business__c}"?`)) {
            this.dispatchEvent(new CustomEvent('delete', { detail: this._record.Id }));
        }
    }
}
