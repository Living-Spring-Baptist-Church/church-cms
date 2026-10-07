/** What the enrolment screen shows. The secret and QR code reach only the person enrolling. */
export type EnrolmentView = {
  readonly factorId: string;
  readonly qrCodeDataUri: string;
  readonly secret: string;
};
