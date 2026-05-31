/**
 * Jest setup. Adds the @testing-library/react-native matchers and silences the
 * RN/Expo logbox noise so the logic-layer tests stay readable. This file is
 * excluded from coverage collection.
 */
import '@testing-library/jest-native/extend-expect';
