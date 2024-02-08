export default {
  computed: {
    getSlaNameErrorMessage() {
      let errorMessage = '';
      if (!this.$v.name.$error) {
        errorMessage = '';
      } else if (!this.$v.name.required) {
        errorMessage = this.$t('SLA.FORM.NAME.REQUIRED_ERROR');
      } else if (!this.$v.name.minLength) {
        errorMessage = this.$t('SLA.FORM.NAME.MINIMUM_LENGTH_ERROR');
      } else if (!this.$v.name.validLabelCharacters) {
        errorMessage = this.$t('SLA.FORM.NAME.VALID_ERROR');
      }
      return errorMessage;
    },
  },
};