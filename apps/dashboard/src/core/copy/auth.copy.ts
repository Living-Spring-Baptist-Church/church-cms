import { IDLE_TIMEOUT_MINUTES, TOTP_CODE_LENGTH } from "@core/data/auth.data";

export const AUTH_COPY = {
  logoAlt: "Living Spring Baptist Church",
  login: {
    pageTitle: "Sign in",
    heading: "Sign in to the staff dashboard",
    description: "Use your church staff email and password.",
    emailLabel: "Email",
    passwordLabel: "Password",
    submit: "Sign in",
    submitting: "Signing in",
    emailInvalid: "Enter a valid email address.",
    passwordRequired: "Enter your password.",
  },
  verify: {
    heading: "Enter your code",
    description: `Open your authenticator app and enter the ${String(TOTP_CODE_LENGTH)} digit code for Living Spring Baptist Church.`,
    codeLabel: "Authentication code",
    codeInvalid: `Enter the ${String(TOTP_CODE_LENGTH)} digit code from your app.`,
    submit: "Verify",
    submitting: "Verifying",
  },
  enrol: {
    heading: "Set up two-factor authentication",
    requiredDescription:
      "Your role needs two-factor authentication. You will use an authenticator app on your phone, and it takes about two minutes.",
    optionalDescription:
      "Add an authenticator app for extra protection. You will enter a code from the app each time you sign in.",
    start: "Start setup",
    starting: "Preparing",
    stepsHeading: "Add this account to your app",
    qrAlt: "QR code to scan with your authenticator app",
    scanInstruction:
      "Scan this QR code with an authenticator app such as Google Authenticator, Microsoft Authenticator or Authy.",
    secretLabel: "Setup key",
    secretHelp: "Cannot scan the code? Enter this key in your app instead.",
    copySecret: "Copy key",
    copiedSecret: "Key copied",
    codeLabel: "Code from your app",
    codeHelp: "Enter the code your app shows to finish setup.",
    submit: "Finish setup",
    submitting: "Checking",
  },
  idleNotice: `You were signed out after ${String(IDLE_TIMEOUT_MINUTES)} minutes without activity. Sign in again to continue.`,
  logout: {
    label: "Sign out",
    pending: "Signing out",
  },
  security: {
    pageTitle: "Account security",
    heading: "Account security",
    enabledHeading: "Two-factor authentication is on",
    enabledDescription:
      "You enter a code from your authenticator app each time you sign in. To change your device, ask a super admin.",
    disabledHeading: "Two-factor authentication is off",
  },
  home: {
    pageTitle: "Home",
    greeting: "Welcome",
    rolesLabel: "Your roles",
    securityLink: "Account security",
    noRoles: "No roles are assigned to your account yet.",
  },
  roleLabels: {
    super_admin: "Super admin",
    pastor: "Pastor",
    treasurer: "Treasurer",
    secretary: "Secretary",
    usher: "Usher",
    department_head: "Department head",
    content_editor: "Content editor",
  },
  shell: {
    skipLink: "Skip to main content",
    homeLinkLabel: "Living Spring Baptist Church home",
    accountNavLabel: "Account",
  },
  errors: {
    heading: "Something went wrong",
    retry: "Try again",
    notFoundHeading: "Page not found",
    notFoundBody: "The page you are looking for does not exist or has moved.",
    notFoundAction: "Go to the home page",
  },
} as const;
