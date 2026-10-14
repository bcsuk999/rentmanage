# Rent Manager --- Complete UI/UX Redesign PRD

**Purpose:** Give Claude a complete, implementation-ready specification
to change the existing Rent Manager application's UI to match the
supplied multi-screen reference image.\
**Scope:** UI/UX redesign only. Preserve the existing backend, APIs,
database, authentication, business rules, and working features unless a
small integration adjustment is necessary for the redesigned UI. Do not
rebuild the product from scratch.

## 1. The exact task

Redesign the existing Rent Manager application so its screens look and
behave like the supplied reference image titled/depicting: 1. Splash /
Loading 2. Rooms Screen 3. Room Details Screen 4. Record Payment Screen
5. Payment Confirmation 6. Overdue Screen 7. Account Screen 8. Loading
Skeleton State 9. Empty State 10. Error / Offline State 11. Filters 12.
Payment History 13. Add Member Form 14. Success Toast 15. Bottom
Navigation / Active Navigation

**The supplied reference image is the visual source of truth.** Match
the same light theme, violet accents, white rounded cards, pale
blue-gray background, compact layout, line icons, green/red/amber
statuses, bottom navigation, and hierarchy. Do not redesign this into a
dark theme or a generic desktop admin panel.

## 2. Non-negotiable implementation constraints

-   Inspect the existing repository first.
-   Keep the current application framework, routing, Node.js backend,
    MongoDB/Mongoose models, API routes, authentication, and business
    logic.
-   Do not create a separate frontend project or a second application.
-   Do not replace existing working APIs with mock APIs.
-   Do not delete working features merely to match the screenshot.
-   Do not hardcode dashboard totals, rooms, users, payment history, or
    balances in production. Use the existing data/API.
-   If an existing endpoint lacks a field needed by the UI, adapt the
    existing integration minimally and document the change.
-   Use the existing project's component system and styling method where
    practical. Do not introduce a large new dependency unless necessary.
-   Make the app responsive and mobile-first while allowing the same UI
    to adapt gracefully to tablet/desktop.
-   The task is complete only when the redesigned UI is connected to
    real existing application data and the key interactions still work.

## 3. Design system

### 3.1 Colour palette

Use these exact design tokens consistently:

  -----------------------------------------------------------------------
  Token                   Hex                     Usage
  ----------------------- ----------------------- -----------------------
  App background          `#F5F7FB`               Main page canvas

  Card/surface            `#FFFFFF`               Cards, sheets, forms

  Primary                 `#635BDB`               Main buttons, selected
                                                  navigation, active
                                                  controls

  Primary pressed         `#5148C8`               Pressed/hover state

  Main text               `#172033`               Titles and important
                                                  information

  Secondary text          `#64748B`               Labels, metadata,
                                                  helper text

  Border                  `#E5E9F2`               Card borders,
                                                  separators, input
                                                  outlines

  Skeleton                `#E6EAF1`               Loading placeholders

  Success                 `#15803D`               Paid, saved, successful

  Success soft            `#DCFCE7`               Paid/success status
                                                  background

  Danger                  `#DC2626`               Overdue, failed,
                                                  destructive

  Danger soft             `#FEE2E2`               Overdue/failed
                                                  background

  Warning                 `#D97706`               Pending, due soon

  Warning soft            `#FEF3C7`               Pending/due-soon
                                                  background

  Neutral chip            `#EEF2F7`               Inactive filter chips
  -----------------------------------------------------------------------

Use coloured status text and soft status pills rather than painting
whole cards in status colours. Status must always have a readable text
label; colour alone is insufficient.

### 3.2 Typography

-   Use a clean modern sans-serif consistent with the reference.
-   Main screen title: 24--28 px, medium/semibold.
-   Section title: 17--20 px, semibold.
-   Card title: 16--18 px, semibold.
-   Standard text: 14--16 px.
-   Metadata: 12--14 px.
-   Monetary values should be easy to scan.
-   Avoid tiny text, excessive boldness, all-caps everywhere, and long
    lines.

### 3.3 Spacing, shape and elevation

-   Use a consistent 4/8 px spacing system.
-   Mobile content padding: approximately 16--20 px.
-   Cards: 14--18 px corner radius.
-   Inputs and buttons: 10--14 px corner radius.
-   Use thin, low-contrast borders and subtle shadows only where they
    help separation.
-   Avoid giant cards, over-large gaps, nested borders around every
    item, and unnecessarily tall lists.
-   Keep the room/member list compact enough to show meaningful
    information without excessive scrolling.

### 3.4 Icons

Use a consistent line icon family. Use building/room, search, plus,
wallet, alert/clock, person, settings, calendar, filter, history,
chevron, check, retry and notification icons as appropriate. Avoid
mixing emojis with line icons. Icon-only buttons need accessible labels.

### 3.5 Responsive layout

-   Mobile is the primary target.
-   The bottom navigation remains fixed at the bottom, with safe-area
    padding.
-   Add bottom content padding so the navigation never covers list items
    or buttons.
-   Forms must remain usable when the on-screen keyboard is open.
-   At wider sizes, expand content naturally with a sensible max width;
    do not simply stretch mobile cards across an ultra-wide screen.
-   No horizontal scrolling for primary page content.
-   Long names, large rupee values and long room IDs must wrap or
    truncate gracefully without clipping.

## 4. Navigation

Use the same three main bottom-navigation items as the reference: -
**Rooms** --- building/room icon. - **Overdue** --- alert/calendar-clock
icon. - **Account** --- user/profile icon.

Styling: - White or near-white navigation surface. - Subtle top
border. - Violet icon/text for the selected item. - Slate icon/text for
inactive items. - Small, restrained active-state background/indicator. -
No oversized active pill. - Fixed positioning with safe-area support. -
Navigation must work and reflect the current route. - Preserve the
previous list's search/filter/scroll state when returning from details
where practical.

## 5. Screen-by-screen UI requirements

### Screen 1 --- Splash / Loading

Purpose: show a branded loading experience while the app starts or
performs a blocking initialization.

Design: - Light `#F5F7FB` background, not black. - Rent Manager
title/logo near the top or centered according to the current app's
branding. - Simple house/property illustration or restrained app icon. -
Short subtitle such as "Manage your rooms, collect rent, stay
organized". - Violet loading indicator near the lower area if needed. -
Avoid an indefinitely displayed splash screen.

Behavior: - If only room data is loading, transition directly to the
Rooms screen with skeleton placeholders rather than blocking the entire
app. - If startup/authentication truly blocks access, show a short
branded loading state. - Show an error/retry path if initialization
fails.

### Screen 2 --- Rooms Screen

This is the default main screen and must closely match the second panel
of the reference image.

#### Header

-   Title: "Rent Manager".
-   Compact header spacing.
-   Optional small selected-period subtitle.
-   Notification icon only if it has a working destination/action;
    otherwise omit it.

#### Summary cards

Show four compact summary values, arranged as a two-column grid on
phones: 1. Rent collected for the selected reporting period. 2.
Outstanding rent for the selected reporting period. 3. Occupied rooms /
total rooms. 4. Total active members.

Each card has a small icon, clear value, and secondary label. Use green
for collected, red for outstanding, violet/blue for room/member counts.
Use actual data from the existing API.

Do not use the sample amounts in the mockup as hardcoded values.

#### Period selector

-   Display the active reporting period.
-   Allow selecting a month or custom date range if supported by
    existing rent data.
-   Make clear that this is a reporting filter, not necessarily each
    tenant's individual rent period.
-   Do not silently change a member's rent cycle to a calendar month.

#### Search and filters

-   Search input placeholder: "Search rooms or members..."
-   Search icon inside the field.
-   Filter icon button at the end of the search row.
-   Search room name/ID and member name/phone using existing API
    capabilities.
-   Show compact filter chips: All, Occupied, Vacant, Partial, Overdue.
    Include Paid/Pending when appropriate and supported.
-   Filters must visibly show selected state and provide a clear/reset
    option.
-   Avoid full-page reloads for normal search/filter changes.

#### Add Room button

-   Violet floating plus button in the lower-right, above bottom
    navigation.
-   Accessible name "Add room".
-   Do not allow it to cover room card content or the navigation.
-   Clicking it opens the existing add-room workflow.

#### Room cards

Each room card is a white rounded rectangle with a subtle border/shadow.
Include: - Room name (e.g. "Dukan room1"). - Room ID if available. -
Occupancy summary (e.g. "2/2 occupied") and occupancy status pill. -
Member payment summary in compact rows or a concise payment breakdown. -
Member name. - Paid/Pending/Partial/Overdue status. - Amount paid,
expected rent and amount due. - Thin progress bar showing collection
progress. - Total outstanding amount for the room. - Small
chevron/eye/details affordance if that matches the existing navigation
pattern.

Keep room cards compact. Do not use the old screen's tall nested member
panels with excessive padding.

#### Room card interactions

-   Tapping a card opens Room Details.
-   Tapping the Add Room button opens Add Room.
-   Search, sorting and filters must update the list.
-   Keep the selected reporting period visible.

### Screen 3 --- Room Details

Match the third panel of the reference image.

#### Top bar

-   Back arrow.
-   Title "Room Details".
-   Optional more-actions menu for Edit/Archive if supported.

#### Room overview

-   Room icon in a softly tinted violet circle.
-   Room name and room ID.
-   Occupancy/capacity summary and status pill.

#### Financial summary

Three compact cards: - Monthly/period rent expected. - Collected
amount. - Remaining amount.

The label should reflect the actual rent-period model; do not call it
"Monthly Rent" if the record is not monthly.

#### Tabs

-   Members
-   Payment History
-   Room Info

Tabs should be compact, with violet active underline/text and no
horizontal overflow.

#### Member cards

For each member show: - Avatar/initial icon. - Name. - Phone number when
permitted. - Rent amount for the selected period. - Paid amount and due
amount. - Payment status pill. - Collection progress bar. - Quick access
to member details or payment recording.

The reference uses a green paid state and red pending/due state. Keep
the same semantic colour system.

#### Bottom actions

-   Primary violet button: "Record Rent Payment".
-   Secondary outlined button: "Add / Edit Member" or the relevant
    member-management action.
-   Do not show actions the current user is not allowed to use.

### Screen 4 --- Record Payment

Match the fourth panel of the reference image.

Top: - Back arrow and title "Record Payment". - Compact room/member
context card with member name, room name and current outstanding
balance.

Form fields: 1. Payment Amount --- required, rupee prefix, numeric
input. 2. Quick amount chips, such as ₹500, ₹1,000, remaining balance,
and Custom; choices should adapt to the actual outstanding balance. 3.
Payment Date --- required, defaults to today. 4. Rent Period ---
required; display explicit Start Date -- End Date. 5. Payment Method ---
required, with options supported by the app, such as Cash, UPI, Bank
Transfer, Other. 6. Transaction Reference --- optional. 7. Notes ---
optional if the existing data model supports them.

Behavior: - Validate the amount is greater than zero. - By default, do
not allow the amount to exceed the outstanding balance unless the
current business rules explicitly support overpayment. - If more than
one rent period is outstanding, require the user to choose which period
is being paid. - Payment date is not the rent period. Store and display
these independently. - Disable the Save Payment button during submission
and show a small progress state. - Prevent duplicate submissions. - On
failure, preserve entered values and show a clear error. - On confirmed
success, navigate to the Payment Confirmation screen or show the app's
established success flow. - Do not fabricate a successful result before
the server confirms persistence.

Primary button: full-width violet "Save Payment".

### Screen 5 --- Payment Confirmation

Match the fifth panel of the reference image.

Design: - Back navigation where appropriate. - Large green checkmark in
a pale green circular area. - Heading: "Payment Recorded!" - Supporting
text with amount, member name and room. - White details card with
amount, payment date, rent period, method and reference. - Primary
violet "Done" button. - Secondary outlined "View Payment History"
button. - Short, restrained check/fade animation.

Rules: - Only show this screen after confirmed successful persistence. -
If the request outcome is uncertain due to a timeout, verify the
transaction before allowing another submission. - Never display a
successful payment result after a failed API request.

### Screen 6 --- Overdue

Match the sixth panel of the reference image.

Header: - Title "Overdue". - Optional functional notification icon.

Summary card: - Total overdue amount. - Number of members/obligations
with overdue balances. - Red/pale-red visual treatment.

Filters: - All - Due Soon - 1--7 Days - 8--30 Days - More than 30 Days

Overdue list cards: - Member name. - Room name and ID. - Outstanding
amount. - Due date. - Rent period Start Date -- End Date. - Number of
days overdue or "Due in N days". - Chevron/details action. - Optional
quick Record Payment action.

Rules: - Do not mark an unpaid obligation overdue before its due date
and any configured grace period. - Partial payment reduces the amount
due but does not mark it paid. - After the server confirms a full
payment, update the list and totals. - Include loading, empty and error
states. - Empty message should explain there are no overdue payments and
avoid a scary warning visual.

### Screen 7 --- Account

Match the seventh panel of the reference image.

Header: - Title "Account". - Settings icon only if it opens a real
settings destination.

Profile section: - Initial/avatar circle. - User's actual display
name. - UID/account ID if the current app has one. - Active status if
supported.

Menu rows use a white rounded card/list style, small coloured icon tile,
title, secondary description, and right chevron. Include only working
features, such as: - Bind Bank / UPI, only if relevant to this
application. - Rent/payment history. - Wallet or balance only if the app
actually implements it. - Settings / password change if authentication
supports it. - Customer Service only if a real contact destination is
configured. - About Rent Manager. - Sign out.

Do not copy gambling/payment-gateway features from another product into
Rent Manager unless they already belong to this app. Do not display dead
links or fake functionality.

### Screen 8 --- Loading Skeleton

Match the eighth panel of the reference image.

-   Keep the normal Rooms page structure.
-   Use light grey-blue skeleton blocks for summary cards, search field,
    filter chips and room cards.
-   Skeletons should roughly match final content dimensions to prevent
    layout shifts.
-   Use a subtle shimmer only if it is not distracting.
-   Do not show the whole app as a blank screen during ordinary data
    loading.
-   Retain already loaded data during refresh.

### Screen 9 --- Empty Rooms State

Match the ninth panel of the reference image.

-   Normal Rent Manager header and bottom navigation remain visible.
-   Center a simple violet/blue illustration or line icon.
-   Heading: "No rooms yet".
-   Supporting copy: "Start by adding your first room to manage rent and
    members."
-   Primary violet "Add Room" button.
-   Keep visual style minimal, airy, and consistent with the light
    theme.

Also create relevant empty states for no filter results, no payment
history, and no overdue obligations.

### Screen 10 --- Error / Offline State

Match the tenth panel of the reference image.

-   Keep the app header and bottom navigation visible.
-   Show a simple network/error illustration or icon.
-   Heading such as "Connection Error".
-   Helpful text: "Unable to load the latest data. Check your internet
    connection and try again."
-   Primary violet "Retry" button.
-   Secondary "Use Cached Data" action only if reliable cached data is
    actually implemented.
-   Do not show a fake offline capability if no cache exists.
-   Never show an indefinite spinner.
-   Preserve form entries if a request fails.
-   Do not claim that a payment was saved offline unless a reliable
    offline queue and reconciliation system exist.

### Screen 11 --- Filters

Match the compact filter sheet/panel in the reference image.

-   Clear heading and Clear action.
-   Group filters with readable labels and accessible controls.
-   Room status: All, Occupied, Vacant.
-   Payment status: All, Paid, Partial, Pending, Overdue.
-   Date range: Start Date and End Date.
-   Room/member filter where relevant.
-   Payment method filter on payment history.
-   Primary "Apply" button.
-   Preserve active filter state when returning to the list.
-   Display active filter chips on the list.
-   Validate that End Date is not before Start Date.

On mobile, use a bottom sheet or full-height filter screen; do not use a
tiny desktop popover.

### Screen 12 --- Payment History

Match the twelfth panel of the reference image.

-   Back arrow and title "Payment History".
-   Optional filters/search above the list.
-   Each row/card shows member name, room, payment date, amount, method,
    rent period, and status where applicable.
-   Use a green Paid/success pill for valid saved payments.
-   Show reference number if present and permitted.
-   Support date-range filter, room/member filter, payment method,
    newest/oldest sort, and reference search.
-   Tapping a record opens details.
-   Corrected/voided payments must remain auditable; do not silently
    erase or overwrite financial history.
-   Provide a proper empty state when there are no records.

### Screen 13 --- Add Member Form

Match the thirteenth panel of the reference image.

Fields: - Full name --- required. - Phone number --- required. - Aadhaar
number --- optional only if the product genuinely needs it. - Room
assignment --- required. - Rent amount --- required. - Rent-cycle start
date --- required. - Rent-cycle end date or configured cycle rule ---
required. - Due date/rule --- as supported by the current data model. -
Move-in date. - Notes --- optional.

UI behavior: - Use clear labels and examples. - Use suitable phone,
numeric, and date inputs. - Inline validation, not just a generic error
at the top. - Save button full width and violet. - Disable while saving
and prevent duplicate submissions. - Preserve form values after
failure. - Show a success toast after confirmed save. - If Aadhaar is
stored, mask it by default, restrict access, and avoid putting it into
logs or search results. - If editing a member, prefill fields from real
data.

### Screen 14 --- Success Toast

-   Small green success toast with check icon.
-   Example copy: "Payment saved successfully!"
-   Short display duration and subtle fade/slide.
-   Do not cover primary actions, form errors, or key financial
    information.
-   Announce important feedback accessibly where supported.
-   Only show after the server confirms the operation succeeded.

### Screen 15 --- Bottom Navigation / Active State

-   Three destinations only: Rooms, Overdue, Account.
-   Icons centred above labels.
-   Violet active icon/label; slate inactive icon/label.
-   White surface, thin top border, subtle selected
    background/indicator.
-   Fixed bottom placement with safe-area support.
-   Content scrolls independently and is padded so it is not hidden by
    navigation.
-   Active state must follow the actual current screen.
-   When opening a secondary screen, preserve the parent tab context.

## 8. Common component specifications

Create reusable components for: - App header - Bottom navigation -
Summary metric card - Room card - Member payment row/card - Status
pill - Collection progress bar - Search input - Filter chip - Date-range
selector - Text/number/date form fields - Primary, secondary, and
destructive buttons - Skeleton cards and list rows - Empty-state panel -
Error/offline panel - Toast/snackbar - Confirmation dialog - Payment
detail row - Loading indicator

Component behaviour, colour, spacing, and typography should be
consistent across all screens. Do not build each screen with unrelated
one-off styles.

## 9. Animation and interaction details

Keep motion restrained and quick: - Tab transition: 120--180 ms. -
Screen transition: 180--240 ms. - Collection progress bar: 250--400
ms. - Button press feedback: immediate and subtle. - Success check:
short fade/scale animation. - Expand/collapse: 180--220 ms. - Skeleton
shimmer: subtle, optional.

Avoid long splash animations, bouncing cards, animated backgrounds, or
animation that delays rent collection. Respect reduced-motion
preferences where supported.

## 10. Financial UI and rent-cycle rules

These rules are essential to correctly displaying the UI:

-   Rent is attached to an explicit **period start date and period end
    date**.
-   Do not assume every rent period is the first to the last day of a
    calendar month.
-   Different members can have different rent cycles.
-   Payment date and rent period are separate.
-   A member can make multiple partial payments for the same rent
    obligation.
-   Expected rent, collected rent and outstanding rent must be distinct
    values.
-   Outstanding = expected amount minus valid payments allocated to the
    selected obligation, subject to the existing business rules.
-   A positive balance before its due date is not automatically overdue.
-   A partial payment reduces outstanding but does not mark the rent
    period Paid.
-   Do not use hardcoded sample amounts from the mockup.
-   Do not update totals optimistically unless the application reliably
    rolls them back on failure; preferably update from confirmed server
    responses.
-   If the existing app has a different documented rent/payment rule,
    preserve it and make the UI accurately reflect it.

## 11. Backend/API integration expectations

This is a UI redesign, not a backend rewrite. Use the existing Node.js
API and Mongoose models.

-   Inspect available endpoints and current response shapes.
-   Map existing data to UI components.
-   Reuse existing endpoints and data models.
-   If the current API lacks a required field, make the smallest
    justified backend adjustment and document it.
-   Do not build fake frontend-only persistence.
-   Use the existing authentication/session method.
-   Handle loading, validation, unauthorized, not-found, conflict,
    server-error and network-error responses.
-   Avoid repeated API requests when switching tabs unnecessarily.
-   Keep API errors user-friendly; do not expose raw database messages.
-   Keep date and money formatting consistent across screens.

## 12. Accessibility and usability

-   Ensure sufficient contrast for all text and controls.
-   Do not rely on colour alone to indicate status.
-   Use accessible labels for icon-only buttons.
-   Provide visible focus states and keyboard navigation where
    appropriate.
-   Associate labels with form fields.
-   Keep touch targets around 44--48 px or larger.
-   Ensure forms remain usable with the mobile keyboard open.
-   Support large text without clipping amounts or labels.
-   Respect reduced-motion preferences where available.
-   Do not place a toast over a form's validation message or primary
    action.

## 13. UI performance requirements

-   Use skeletons instead of a blank screen.
-   Retain existing data during refresh.
-   Debounce search.
-   Use pagination or incremental loading for long histories.
-   Avoid unnecessary full-screen reloads.
-   Avoid layout shifts when data loads.
-   Keep filters and scroll positions when returning from details where
    practical.
-   Make buttons visibly respond immediately.
-   Ensure the bottom navigation does not cover the final list item or
    focused field.

## 14. Implementation plan

Implement in this order:

1.  Inspect the existing repository, UI framework, routes, components,
    API endpoints, and current styles.
2.  Establish the design tokens and shared components from this PRD.
3.  Redesign the bottom navigation and app shell.
4.  Redesign the Rooms screen, including summaries, search, filters,
    room cards, and Add Room action.
5.  Redesign Room Details and member cards.
6.  Redesign Record Payment and Payment Confirmation.
7.  Redesign Overdue.
8.  Redesign Account.
9.  Redesign Filters, Payment History, and Add/Edit Member.
10. Implement all loading, empty, error/offline, validation, and success
    states.
11. Connect every screen to the existing API.
12. Test mobile widths, larger screens, keyboard behaviour, navigation,
    long names, large amounts, partial payments, and failed requests.
13. Compare screenshots against the supplied reference image and refine
    spacing, typography, colours, card heights, and alignment.
14. Report what changed, what existing functionality was preserved, and
    any limitations.

## 15. Explicit instructions to Claude

-   Treat the supplied UI collage image as the design reference and this
    PRD as the behaviour specification.
-   Match the visual design as closely as possible; do not substitute a
    dark theme or a generic admin dashboard.
-   This task is to change the existing app's UI. Do not rebuild the
    whole application or replace the database/API architecture.
-   Do not stop after creating static mockups; implement real screens
    wired to real data.
-   Do not remove existing working features.
-   Do not use hardcoded dashboard values in production.
-   Implement all screens and states listed in this document, not only
    the Rooms screen.
-   Verify every button and navigation item performs its intended
    action.
-   If the current repository differs from the PRD, inspect it first and
    preserve working behaviour unless a change is necessary.
-   Do not add unrequested payment gateways or external integrations.
-   Before completion, run the available tests/build and manually verify
    the core flows.

## 16. Final delivery checklist

-   [ ] Rooms screen visually matches the reference.
-   [ ] Room Details screen implemented.
-   [ ] Record Payment screen implemented.
-   [ ] Payment Confirmation implemented.
-   [ ] Overdue screen implemented.
-   [ ] Account screen implemented.
-   [ ] Loading skeleton state implemented.
-   [ ] Empty Rooms state implemented.
-   [ ] Error/Offline state implemented.
-   [ ] Filters implemented.
-   [ ] Payment History implemented.
-   [ ] Add/Edit Member form implemented.
-   [ ] Success toast implemented.
-   [ ] Bottom navigation implemented.
-   [ ] All UI uses the same design tokens.
-   [ ] Existing APIs and business rules are preserved.
-   [ ] Real data is displayed instead of hardcoded production values.
-   [ ] Partial payment and rent-period displays are correct.
-   [ ] Search and filters work.
-   [ ] Failed requests never show false success.
-   [ ] No infinite loading spinner.
-   [ ] Mobile safe areas and bottom navigation overlap tested.
-   [ ] Build/tests run and results reported.
